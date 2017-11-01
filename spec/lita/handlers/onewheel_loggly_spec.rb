require 'spec_helper'

def mock_it_up(file)
  mock_result_json = File.open("spec/fixtures/#{file}.json").read
  response = {}
  allow(response).to receive(:body).and_return(mock_result_json)
  allow(RestClient).to receive(:get).and_return(response)
end

describe Lita::Handlers::OnewheelLoggly, lita_handler: true do

  before(:each) do
    registry.configure do |config|
      config.handlers.onewheel_loggly.api_key = 'xyz'
      config.handlers.onewheel_loggly.base_uri = ''
      config.handlers.onewheel_loggly.query = ''
    end
  end

  it { is_expected.to route_command('logs -10m') }
  it { is_expected.to route_command('logs') }

  it 'does neat loggly things' do
    mock_it_up('mock_result')

    send_command 'logs 10m'
    expect(replies.last).to eq('Counted 1: Unhandled http.client.RemoteDisconnected: Remote end closed connection without response')
  end
end
