require 'spec_helper'

def mock_it_up(file)
  mock_result_json = File.open("spec/fixtures/#{file}.json").read
  allow(RestClient).to receive(:get).and_return({body: mock_result_json})
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
    expect(replies.last).to eq('https://s-media-cache-ak0.pinimg.com/736x/4a/43/a4/4a43a4b6569cf8a197b6c9217de3f412.jpg')
  end
end
