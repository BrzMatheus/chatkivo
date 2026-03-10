require 'stringio'

class Evolution::ImportHistoryJob < ApplicationJob
  queue_as :low
  retry_on ActiveStorage::FileNotFoundError, wait: 1.minute, attempts: 3
  retry_on StandardError, wait: 2.minutes, attempts: 2

  def perform(data_import_id, inbox_id, dry_run: true)
    @data_import = DataImport.find(data_import_id)
    @inbox = @data_import.account.inboxes.find(inbox_id)

    process_import(dry_run)
  rescue StandardError => e
    handle_error(e)
    raise
  end

  private

  def process_import(dry_run)
    @data_import.update!(status: :processing, processing_errors: nil)

    result = Evolution::ImportHistoryService.new(
      account: @data_import.account,
      inbox: @inbox,
      import_file_data: @data_import.import_file.download,
      dry_run: dry_run
    ).perform

    attach_report(result[:report_csv])

    @data_import.update!(
      status: :completed,
      processed_records: result[:processed_records],
      total_records: result[:total_records],
      processing_errors: result[:errors].presence&.join("\n")
    )
  end

  def attach_report(report_csv)
    return if report_csv.blank?

    filename = "evolution_import_report_#{Time.current.strftime('%Y%m%d_%H%M%S')}.csv"
    @data_import.failed_records.purge if @data_import.failed_records.attached?
    @data_import.failed_records.attach(
      io: StringIO.new(report_csv),
      filename: filename,
      content_type: 'text/csv'
    )
  end

  def handle_error(error)
    return unless @data_import

    @data_import.update!(
      status: :failed,
      processing_errors: error.message
    )

    Rails.logger.error "Evolution import failed for data_import #{@data_import.id}: #{error.message}"
    Rails.logger.error error.backtrace.join("\n")
  end
end
