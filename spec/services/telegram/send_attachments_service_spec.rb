require 'rails_helper'

RSpec.describe Telegram::SendAttachmentsService do
  describe '#perform' do
    let(:channel) { create(:channel_telegram) }
    let(:message) { build(:message, conversation: create(:conversation, inbox: channel.inbox)) }
    let(:service) { described_class.new(message: message) }
    let(:telegram_api_url) { channel.telegram_api_url }

    before do
      allow(channel).to receive(:chat_id).and_return('chat123')

      stub_request(:post, "#{telegram_api_url}/sendPhoto")
        .to_return(status: 200, body: { ok: true, result: { message_id: 'photo' } }.to_json, headers: { 'Content-Type' => 'application/json' })

      stub_request(:post, "#{telegram_api_url}/sendVideo")
        .to_return(status: 200, body: { ok: true, result: { message_id: 'video' } }.to_json, headers: { 'Content-Type' => 'application/json' })

      stub_request(:post, "#{telegram_api_url}/sendAudio")
        .to_return(status: 200, body: { ok: true, result: { message_id: 'audio' } }.to_json, headers: { 'Content-Type' => 'application/json' })

      stub_request(:post, "#{telegram_api_url}/sendDocument")
        .to_return(status: 200, body: { ok: true, result: { message_id: 'document' } }.to_json, headers: { 'Content-Type' => 'application/json' })
    end

    it 'sends all types of attachments individually and returns the last successful message ID' do
      attach_files(message)
      result = service.perform
      expect(result).to eq('document')
      expect(a_request(:post, "#{telegram_api_url}/sendPhoto")).to have_been_made.once
      expect(a_request(:post, "#{telegram_api_url}/sendVideo")).to have_been_made.once
      expect(a_request(:post, "#{telegram_api_url}/sendAudio")).to have_been_made.once
      expect(a_request(:post, "#{telegram_api_url}/sendDocument")).to have_been_made.once
    end

    context 'when all attachments are documents' do
      before do
        2.times { attach_file_to_message(message, 'file', 'sample.pdf', 'application/pdf') }
        message.save!
      end

      it 'sends documents individually and returns the message ID of the last successful document' do
        result = service.perform
        expect(result).to eq('document')
        expect(a_request(:post, "#{telegram_api_url}/sendDocument")).to have_been_made.times(2)
      end
    end

    context 'when this is business chat' do
      before { allow(channel).to receive(:business_connection_id).and_return('eooW3KF5WB5HxTD7T826') }

      it 'sends all attachments with business_connection_id' do
        attach_files(message)
        service.perform

        expect(a_request(:post, "#{telegram_api_url}/sendPhoto")
          .with { |req| req.body =~ /business_connection_id.+eooW3KF5WB5HxTD7T826/m })
          .to have_been_made.once

        expect(a_request(:post, "#{telegram_api_url}/sendVideo")
          .with { |req| req.body =~ /business_connection_id.+eooW3KF5WB5HxTD7T826/m })
          .to have_been_made.once

        expect(a_request(:post, "#{telegram_api_url}/sendAudio")
          .with { |req| req.body =~ /business_connection_id.+eooW3KF5WB5HxTD7T826/m })
          .to have_been_made.once

        expect(a_request(:post, "#{telegram_api_url}/sendDocument")
          .with { |req| req.body =~ /business_connection_id.+eooW3KF5WB5HxTD7T826/m })
          .to have_been_made.once
      end
    end

    context 'when all attachments are photo and video' do
      before do
        2.times { attach_file_to_message(message, 'image', 'sample.png', 'image/png') }
        attach_file_to_message(message, 'video', 'sample.mp4', 'video/mp4')
        message.save!
      end

      it 'sends each attachment individually and returns the last message ID' do
        result = service.perform
        expect(result).to eq('video')
        expect(a_request(:post, "#{telegram_api_url}/sendPhoto")).to have_been_made.times(2)
        expect(a_request(:post, "#{telegram_api_url}/sendVideo")).to have_been_made.once
      end
    end

    context 'when all attachments are audio' do
      before do
        2.times { attach_file_to_message(message, 'audio', 'sample.mp3', 'audio/mpeg') }
        message.save!
      end

      it 'sends audio messages individually and returns the last message ID' do
        result = service.perform
        expect(result).to eq('audio')
        expect(a_request(:post, "#{telegram_api_url}/sendAudio")).to have_been_made.times(2)
      end
    end

    context 'when all attachments are photos, videos, and audio' do
      before do
        attach_file_to_message(message, 'image', 'sample.png', 'image/png')
        attach_file_to_message(message, 'video', 'sample.mp4', 'video/mp4')
        attach_file_to_message(message, 'audio', 'sample.mp3', 'audio/mpeg')
        message.save!
      end

      it 'sends each attachment individually' do
        result = service.perform
        expect(result).to eq('audio')
        expect(a_request(:post, "#{telegram_api_url}/sendPhoto")).to have_been_made.once
        expect(a_request(:post, "#{telegram_api_url}/sendVideo")).to have_been_made.once
        expect(a_request(:post, "#{telegram_api_url}/sendAudio")).to have_been_made.once
      end
    end

    context 'when an attachment fails to send' do
      before do
        stub_request(:post, "#{telegram_api_url}/sendDocument")
          .to_return(status: 500, body: { ok: false,
                                          description: 'Internal server error' }.to_json, headers: { 'Content-Type' => 'application/json' })
      end

      it 'logs an error, stops processing, and returns nil' do
        attach_file_to_message(message, 'file', 'sample.pdf', 'application/pdf')
        attach_file_to_message(message, 'image', 'sample.png', 'image/png')
        message.save!

        expect(Rails.logger).to receive(:error).at_least(:once)
        result = service.perform
        expect(result).to be_nil
        # Should stop after the first failure (document is processed first in the order)
        expect(a_request(:post, "#{telegram_api_url}/sendDocument")).to have_been_made.once
      end
    end

    def attach_files(message)
      attach_file_to_message(message, 'image', 'sample.png', 'image/png')
      attach_file_to_message(message, 'video', 'sample.mp4', 'video/mp4')
      attach_file_to_message(message, 'audio', 'sample.mp3', 'audio/mpeg')
      attach_file_to_message(message, 'file', 'sample.pdf', 'application/pdf')
      message.save!
    end

    def attach_file_to_message(message, type, filename, content_type)
      attachment = message.attachments.new(account_id: message.account_id, file_type: type)
      attachment.file.attach(io: Rails.root.join("spec/assets/#{filename}").open, filename: filename, content_type: content_type)
    end
  end
end
