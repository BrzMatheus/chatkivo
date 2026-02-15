# frozen_string_literal: true

# Diagnose Telegram pipeline health through Sidekiq + DB signals.
#
# Usage:
#   RAILS_ENV=production bundle exec rails runner script/telegram_sidekiq_diagnostic.rb [HOURS_BACK]
#
# Examples:
#   RAILS_ENV=production bundle exec rails runner script/telegram_sidekiq_diagnostic.rb
#   RAILS_ENV=production bundle exec rails runner script/telegram_sidekiq_diagnostic.rb 24
#
# This script is read-only and prints:
# - queue sizes and Telegram-related jobs enqueued
# - retry/dead jobs for Telegram pipeline
# - recent failed outgoing Telegram messages
# - recent outgoing messages with source_id missing (likely not delivered to provider)
# - recent incoming Telegram activity

require 'sidekiq/api'

class TelegramSidekiqDiagnostic
  TELEGRAM_RELEVANT_JOB_CLASSES = [
    'Webhooks::TelegramEventsJob',
    'SendReplyJob'
  ].freeze

  QUEUES_TO_CHECK = %w[
    critical
    high
    medium
    default
    low
  ].freeze

  def initialize(hours_back:)
    @hours_back = hours_back
    @since_time = hours_back.hours.ago
  end

  def run
    print_header
    print_process_summary
    print_queue_summary
    print_retry_summary
    print_dead_summary
    print_db_signals
    print_action_hints
  end

  private

  attr_reader :hours_back, :since_time

  def print_header
    puts '=' * 100
    puts 'Telegram + Sidekiq Diagnostic'
    puts '=' * 100
    puts "Generated at: #{Time.current.utc.iso8601}"
    puts "Window start: #{since_time.utc.iso8601} (last #{hours_back}h)"
    puts "Rails env: #{Rails.env}"
    puts '=' * 100
    puts
  end

  def print_process_summary
    puts 'Sidekiq Processes'
    puts '-' * 100
    processes = Sidekiq::ProcessSet.new
    puts "Active processes: #{processes.size}"
    processes.each do |process|
      queues = process['queues'] || []
      puts "  pid=#{process['pid']} host=#{process['hostname']} busy=#{process['busy']} concurrency=#{process['concurrency']} queues=#{queues.join(',')}"
    end
    puts
  end

  def print_queue_summary
    puts 'Queue Backlog'
    puts '-' * 100

    QUEUES_TO_CHECK.each do |queue_name|
      queue = Sidekiq::Queue.new(queue_name)
      telegram_jobs = 0
      sampled = 0

      queue.each do |job|
        sampled += 1
        wrapped = job.item['wrapped'] || job.item['class']
        telegram_jobs += 1 if TELEGRAM_RELEVANT_JOB_CLASSES.include?(wrapped)
        break if sampled >= 5000
      end

      puts "  queue=#{queue_name.ljust(8)} size=#{queue.size.to_s.ljust(8)} telegram_related_jobs(sampled)=#{telegram_jobs}"
    end
    puts
  end

  def print_retry_summary
    puts 'Retry Set (Telegram-related)'
    puts '-' * 100

    retry_set = Sidekiq::RetrySet.new
    matches = []
    retry_set.each do |job|
      wrapped = job.item['wrapped'] || job.item['class']
      next unless TELEGRAM_RELEVANT_JOB_CLASSES.include?(wrapped)

      matches << {
        jid: job.jid,
        klass: wrapped,
        queue: job.queue,
        retry_count: job.item['retry_count'],
        failed_at: epoch_to_time(job.item['failed_at']),
        error_class: job.item['error_class'],
        error_message: job.item['error_message']
      }
      break if matches.size >= 30
    end

    puts "  total_retry_size=#{retry_set.size}"
    if matches.empty?
      puts '  no Telegram-related jobs in retry'
    else
      matches.each do |item|
        puts "  jid=#{item[:jid]} class=#{item[:klass]} queue=#{item[:queue]} retry_count=#{item[:retry_count]} failed_at=#{item[:failed_at]}"
        puts "    error=#{item[:error_class]}: #{item[:error_message]}"
      end
    end
    puts
  end

  def print_dead_summary
    puts 'Dead Set (Telegram-related)'
    puts '-' * 100

    dead_set = Sidekiq::DeadSet.new
    matches = []
    dead_set.each do |job|
      wrapped = job.item['wrapped'] || job.item['class']
      next unless TELEGRAM_RELEVANT_JOB_CLASSES.include?(wrapped)

      matches << {
        jid: job.jid,
        klass: wrapped,
        queue: job.queue,
        died_at: epoch_to_time(job.item['failed_at']),
        error_class: job.item['error_class'],
        error_message: job.item['error_message']
      }
      break if matches.size >= 30
    end

    puts "  total_dead_size=#{dead_set.size}"
    if matches.empty?
      puts '  no Telegram-related jobs in dead set'
    else
      matches.each do |item|
        puts "  jid=#{item[:jid]} class=#{item[:klass]} queue=#{item[:queue]} died_at=#{item[:died_at]}"
        puts "    error=#{item[:error_class]}: #{item[:error_message]}"
      end
    end
    puts
  end

  def print_db_signals
    puts 'Database Signals (Telegram)'
    puts '-' * 100

    telegram_inboxes = Inbox.where(channel_type: 'Channel::Telegram').pluck(:id)
    puts "Telegram inboxes: #{telegram_inboxes.size}"
    return puts if telegram_inboxes.empty?

    outgoing_recent = Message
                      .joins(:conversation)
                      .where(conversations: { inbox_id: telegram_inboxes })
                      .where(message_type: Message.message_types[:outgoing])
                      .where('messages.created_at >= ?', since_time)

    incoming_recent = Message
                      .joins(:conversation)
                      .where(conversations: { inbox_id: telegram_inboxes })
                      .where(message_type: Message.message_types[:incoming])
                      .where('messages.created_at >= ?', since_time)

    failed_outgoing = outgoing_recent.where(status: Message.statuses[:failed])
    peer_id_failures = failed_outgoing.where("messages.content_attributes ->> 'external_error' ILIKE ?", '%PEER_ID_INVALID%')
    no_source_id_count = outgoing_recent.where(source_id: [nil, '']).count

    puts "Outgoing recent: #{outgoing_recent.count}"
    puts "Incoming recent: #{incoming_recent.count}"
    puts "Failed outgoing recent: #{failed_outgoing.count}"
    puts "PEER_ID_INVALID recent: #{peer_id_failures.count}"
    puts "Outgoing recent with source_id missing: #{no_source_id_count}"
    puts

    recent_failures = peer_id_failures.order(created_at: :desc).limit(20)
    return unless recent_failures.any?

    puts 'Last PEER_ID_INVALID messages:'
    recent_failures.each do |message|
      puts "  message_id=#{message.id} conversation_id=#{message.conversation_id} created_at=#{message.created_at.utc.iso8601}"
      puts "    external_error=#{message.content_attributes&.dig('external_error').inspect}"
    end
    puts
  end

  def print_action_hints
    puts 'Interpretation Hints'
    puts '-' * 100
    puts '- If Active processes = 0, Sidekiq is down (Telegram send/receive will stop).'
    puts '- If default/high queues are growing, workers are not consuming the queues Telegram needs.'
    puts '- If retry/dead has Webhooks::TelegramEventsJob, inbound webhook processing is failing.'
    puts '- If retry/dead has SendReplyJob, outbound sends are failing before or during provider call.'
    puts '- If critical queue is permanently large, strict queue order can starve high/default.'
    puts
  end

  def epoch_to_time(epoch_value)
    return nil if epoch_value.blank?

    Time.at(epoch_value).utc.iso8601
  rescue StandardError
    nil
  end
end

hours_back = (ARGV[0] || 6).to_i

TelegramSidekiqDiagnostic.new(hours_back: hours_back).run
