# frozen_string_literal: true

# Run with:
#   bundle exec rake chatwoot:ops:cleanup_orphan_blobs
#   bundle exec rake chatwoot:ops:cleanup_orphan_blobs[dry_run]

namespace :chatwoot do
  namespace :ops do
    desc 'Identify and delete Active Storage blobs without physical files'
    task :cleanup_orphan_blobs, [:mode] => :environment do |_task, args|
      dry_run = args[:mode] == 'dry_run'
      orphan_blobs = []
      checked_count = 0
      batch_size = 100

      puts "Mode: #{dry_run ? 'DRY RUN (no deletions)' : 'LIVE (will delete orphan blobs)'}"
      puts 'Scanning Active Storage blobs...'
      puts '-' * 50

      ActiveStorage::Blob.find_each(batch_size: batch_size) do |blob|
        checked_count += 1
        print "\rChecked #{checked_count} blobs..." if (checked_count % batch_size).zero?

        # Check if the blob's file exists in storage
        unless blob_file_exists?(blob)
          orphan_blobs << {
            id: blob.id,
            key: blob.key,
            filename: blob.filename.to_s,
            content_type: blob.content_type,
            created_at: blob.created_at
          }
        end
      end

      puts "\n" + '-' * 50
      puts "Total blobs checked: #{checked_count}"
      puts "Orphan blobs found: #{orphan_blobs.count}"

      if orphan_blobs.any?
        puts "\nOrphan blobs details:"
        orphan_blobs.first(10).each do |blob_info|
          puts "  - ID: #{blob_info[:id]}, Filename: #{blob_info[:filename]}, Created: #{blob_info[:created_at]}"
        end
        puts "  ... and #{orphan_blobs.count - 10} more" if orphan_blobs.count > 10

        unless dry_run
          print "\nDo you want to delete these #{orphan_blobs.count} orphan blobs? (y/N): "
          confirm = $stdin.gets.strip.downcase

          if %w[y yes].include?(confirm)
            deleted_count = 0
            orphan_blobs.each do |blob_info|
              blob = ActiveStorage::Blob.find_by(id: blob_info[:id])
              next unless blob

              # Delete attachments first, then the blob
              blob.attachments.destroy_all
              blob.destroy
              deleted_count += 1
              print "\rDeleted #{deleted_count} blobs..." if (deleted_count % 10).zero?
            end
            puts "\n#{deleted_count} orphan blobs deleted successfully."
          else
            puts 'No blobs were deleted.'
          end
        end
      else
        puts 'No orphan blobs found. Storage is clean!'
      end
    end

    private

    def blob_file_exists?(blob)
      blob.service.exist?(blob.key)
    rescue StandardError => e
      Rails.logger.warn "Error checking blob #{blob.id}: #{e.message}"
      # If we can't check, assume it exists to be safe
      true
    end
  end
end


