require 'spec_helper'

def mock_it_up(file)
  mock_result = File.open("spec/fixtures/mock_result.json").read
  next_mock_result = File.open("spec/fixtures/mock_next_result.json").read

  auth_header = {'Authorization': 'bearer xyz'}
  uri = '/iterate?q=&from=-10m&until=&size=1000'
  next_uri = 'https://lululemon.loggly.com/apiv2/events/iterate?next=9cb4b38a-37d7-43d3-ad79-063cf2d1c43c'

  response = {}
  allow(response).to receive(:body).and_return(mock_result)
  next_response = {}
  allow(next_response).to receive(:body).and_return(next_mock_result)

  allow(RestClient).to receive(:get).with(uri, auth_header).and_return(response)
  allow(RestClient).to receive(:get).with(next_uri, auth_header).and_return(next_response)
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
