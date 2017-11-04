require 'spec_helper'

def mock_it_up(file)
  mock_result = File.open("spec/fixtures/mock_result.json").read
  next_mock_result = File.open("spec/fixtures/mock_next_result.json").read
  oneoff_mock_result = File.open("spec/fixtures/oneoff.json").read
  total_requests_mock_result = File.open("spec/fixtures/total_requests.json").read
  rsid_mock_result = File.open("spec/fixtures/rsid.json").read

  auth_header = {'Authorization': 'bearer xyz'}
  uri = '/iterate?q=&from=-10m&until=&size=1000'
  next_uri = 'https://lululemon.loggly.com/apiv2/events/iterate?next=9cb4b38a-37d7-43d3-ad79-063cf2d1c43c'
  oneoff_uri = '/iterate?q=%22translation--prod-%22+%22status%3D404%22+-%22return+to+FE%22&from=2017-11-02T10:00:00Z&until=2017-11-03T16:00:00Z&size=1000'
  total_requests_uri = "http://lululemon.loggly.com/apiv2/search?q=%22translation--prod-%22+%22request+START%22&from=-10m&until=now"
  rsid_uri = "http://lululemon.loggly.com/apiv2/events?rsid=86162304"

  response = {}
  allow(response).to receive(:body).and_return(mock_result)
  next_response = {}
  allow(next_response).to receive(:body).and_return(next_mock_result)
  oneoff_response = {}
  allow(oneoff_response).to receive(:body).and_return(oneoff_mock_result)
  total_requests_response = {}
  allow(total_requests_response).to receive(:body).and_return(total_requests_mock_result)
  rsid_response = {}
  allow(rsid_response).to receive(:body).and_return(rsid_mock_result)

  allow(RestClient).to receive(:get).with(uri, auth_header).and_return(response)
  allow(RestClient).to receive(:get).with(next_uri, auth_header).and_return(next_response)
  allow(RestClient).to receive(:get).with(oneoff_uri, auth_header).and_return(oneoff_response)
  allow(RestClient).to receive(:get).with(total_requests_uri, auth_header).and_return(total_requests_response)
  allow(RestClient).to receive(:get).with(rsid_uri, auth_header).and_return(rsid_response)
end

describe Lita::Handlers::OnewheelLoggly, lita_handler: true do

  before(:each) do
    registry.configure do |config|
      config.handlers.onewheel_loggly.api_key = 'xyz'
      config.handlers.onewheel_loggly.base_uri = ''
      config.handlers.onewheel_loggly.query = ''
      config.handlers.onewheel_loggly.requests_query = ''
    end
  end

  it { is_expected.to route_command('logs -10m') }
  it { is_expected.to route_command('logs') }

  it 'does neat loggly things' do
    mock_it_up('mock_result')

    send_command 'logs 10m'
    expect(replies.last).to include('Counted 23: fault=call.atg.resp')
  end

  it 'does neat loggly things' do
    mock_it_up('oneoff_fixture')

    send_command 'oneoff'
    expect(replies.last).to include('oneoff_report.csv created.')
  end

  it 'does a total event count' do
    mock_it_up('rsid')

    send_command 'logs'
    expect(replies[1]).to include('53137 requests')
  end
end
