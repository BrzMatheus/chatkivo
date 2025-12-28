class Telegram::ImportHistoryJob < ApplicationJob
  queue_as :low
  retry_on ActiveStorage::FileNotFoundError, wait: 1.minute, attempts: 3
  retry_on StandardError, wait: 2.minutes, attempts: 2

  def perform(data_import_id, inbox_id)
    @data_import = DataImport.find(data_import_id)
    @inbox = @data_import.account.inboxes.find(inbox_id)

    process_import
  rescue StandardError => e
    handle_error(e)
    raise
  end

  private

  def process_import
    @data_import.update!(status: :processing)

    import_file_data = @data_import.import_file.download

    result = Telegram::ImportHistoryService.new(
      account: @data_import.account,
      inbox: @inbox,
      import_file_data: import_file_data
    ).perform

    @data_import.update!(
      status: :completed,
      processed_records: result[:messages_count],
      total_records: result[:messages_count]
    )
  end

  def handle_error(error)
    @data_import.update!(
      status: :failed,
      processing_errors: error.message
    )
    Rails.logger.error "Telegram import failed for data_import #{@data_import.id}: #{error.message}"
    Rails.logger.error error.backtrace.join("\n")
  end
end
