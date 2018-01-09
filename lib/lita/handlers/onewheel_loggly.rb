require 'json'
require 'rest-client'

module Lita
  module Handlers
    class OnewheelLoggly < Handler
      config :api_key, required: true
      config :base_uri, required: true
      config :query, required: true
      config :requests_query, required: true

      route /^logs\s+([\w-]+)$/i, :logs, command: true
      route /^logs$/i, :logs, command: true
      route /^oneoff$/i, :oneoff, command: true
      route /^oneoffendeca$/i, :oneoff_endeca, command: true
      route /^rollup\s+([\w=.-]+)\s*([-0-9smhd]*)$/i, :rollup, command: true
      route /^hourlyoneoff$/i, :hourly_oneoff, command: true
      route /^hourlyrollup$/i, :hourly_oneoff, command: true
      route /^hourlyrunoff$/i, :hourly_oneoff, command: true

      # Run a query through loggly
      # Group logs by req_url, return counts
      def rollup(response)

        # Run query through loggly
        from_time = get_from_time(response.matches[0][1])
        query = "\"translation--prod\" \"#{response.matches[0][0]}\""
        uri = get_pagination_uri(from_time, response, query)
        events = call_loggly(uri)
        counts_by_url_total = {}

        loop do #run at least once
          counts_by_url_this_loop = rollup_events(events)
          # copy totals of this event into master hash
          counts_by_url_total = merge_hash_with_counts(counts_by_url_total, counts_by_url_this_loop)
          Lita.logger.debug "totals_count = #{counts_by_url_total.length}"
          Lita.logger.debug "events_count = #{counts_by_url_this_loop.length}"
          break if events['next'].nil?
          events = call_loggly(events['next'])
        end

        replies = "Top 11 URLs by incidence count:\n\n"
        counts_by_url_total = counts_by_url_total.sort_by { |_k, v| -v }
        counts_by_url_total.each_with_index do |(key, count), index|
          replies += "Counted #{count}: #{key}\n"
          break if index >= 10
        end

        replies += "\n#{counts_by_url_total.count} unique URLs with errors."
        Lita.logger.debug replies
        response.reply "```#{replies}```"
      end

      def logs(response)

        from_time = get_from_time(response.matches[0][0])

        total_request_count = get_total_request_count(from_time)

        uri = get_pagination_uri(from_time, response)
        events = call_loggly(uri)
        # Todo: Capture that exception, print and return

        alerts = Hash.new { |h, k| h[k] = 0 }
        alerts = process_event(events, alerts)

        events_count = events['events'].count
        Lita.logger.debug "events_count = #{events_count}"

        while events['next'] do
          events = call_loggly(events['next'])
          events_count += events['events'].count
          Lita.logger.debug "events_count = #{events_count}"

          alerts = process_event(events, alerts)
        end

        Lita.logger.debug "#{events_count} events"

        events_as_percentage = get_percentage_of_requests(events_count, total_request_count)
        replies = "#{total_request_count} requests\n#{events_count} events (#{events_as_percentage}%)\n\n"
        alerts = alerts.sort_by { |_k, v| -v }
        alerts.each do |key, count|
          event_percent = get_percentage_of_requests(count, total_request_count)
          replies += "Counted #{count} (#{event_percent}%): #{key}\n"
        end

        Lita.logger.debug replies
        response.reply "```#{replies}```"
      end

      def get_percentage_of_requests(events_count, total_request_count)
        ((events_count.to_f / total_request_count) * 100).round(3)
      end

      def get_from_time(from_time_param)
        from_time = '-10m'
        if /\d+/.match from_time_param
          Lita.logger.debug "Suspected time: #{from_time_param}"
          from_time = from_time_param
          unless from_time[0] == '-'
            from_time = "-#{from_time}"
          end
        end
        from_time
      end

      def get_total_request_count(from_time)
        # Getting the total events count is a texas two-step...

        uri = "http://lululemon.loggly.com/apiv2/search?q=#{CGI::escape config.requests_query}&from=#{from_time}&until=now"

        rsid_response = call_loggly(uri)
        rsid = rsid_response['rsid']['id']

        events = call_loggly("http://lululemon.loggly.com/apiv2/events?rsid=#{rsid}")
        Lita.logger.debug "Total requests count: #{events['total_events']}"
        events['total_events']
      end

      def call_loggly(uri)
        begin
          auth_header = {'Authorization': "bearer #{config.api_key}"}
          Lita.logger.debug uri
          resp = RestClient.get uri, auth_header
        rescue StandardError => timeout_exception
          Lita.logger.debug "Error: #{timeout_exception}"
          return timeout_exception
        end
        JSON.parse resp.body
      end

      def get_pagination_uri(from_time, response, query=nil)
        query_term = query.nil?? config.query : query
        response.reply "Gathering `#{query_term}` events from #{from_time}..."
        sample_query = "/iterate?q=#{CGI::escape query_term}&from=#{from_time}&until=&size=1000"
        "#{config.base_uri}#{sample_query}"
      end

      def oneoff(response)
        auth_header = {'Authorization': "bearer #{config.api_key}"}

        query = '"translation--prod-" "status=404" -"return to FE"'
        sample_query = "/iterate?q=#{CGI::escape query}&from=2017-11-02T10:00:00Z&until=2017-11-03T16:00:00Z&size=1000"
        uri = "#{config.base_uri}#{sample_query}"
        Lita.logger.debug uri

        begin
          resp = RestClient.get uri, auth_header
        rescue Exception => timeout_exception
          response.reply "Error: #{timeout_exception}"
          return
        end

        alerts = Hash.new { |h, k| h[k] = 0 }

        master_events = []
        events = JSON.parse resp.body
        # alerts = process_event(events, alerts)
        events_count = events['events'].count
        Lita.logger.debug "events_count = #{events_count}"

        events['events'].each do |eve|
          master_events.push eve['event']['json']['message']
        end

        while events['next'] do
          Lita.logger.debug "Getting next #{events['next']}"
          resp = get_events_from_loggly(auth_header, events)
          events = JSON.parse resp.body
          events['events'].each do |eve|
            master_events.push eve['event']['json']['message']
          end
          # alerts = process_event(events, alerts)
        end

        Lita.logger.debug "#{events_count} events"
        response.reply "#{events_count} events"
        Lita.logger.debug "#{master_events.count} events"
        response.reply "#{master_events.count} events"

        url_list = []
        master_events.each do |message|
          if md = /,\s+url=([^,]+),/.match(message)
            Lita.logger.debug md.captures[0]
            url_list.push md.captures[0]
          end
        end

        url_list.each do |url|
          alerts[url] += 1
        end


        file = File.open("oneoff_report.csv", "w")
        # replies = ''
        alerts = alerts.sort_by { |_k, v| -v }
        alerts.each do |key, count|
          # Lita.logger.debug "Counted #{count}: #{key}"
          # replies += "Counted #{count}: #{key}\n"
          file.write("#{count},#{key}\n")
        end

        file.close
        response.reply "oneoff_report.csv created."
      end

      def oneoff_endeca(response)
        auth_header = {'Authorization': "bearer #{config.api_key}"}

        query = 'json.level:ERROR  ("call.endeca.malformed-resp-payload")'
        sample_query = "/iterate?q=#{CGI::escape query}&from=-12h&until=&size=1000"
        uri = "#{config.base_uri}#{sample_query}"
        Lita.logger.debug uri

        begin
          resp = RestClient.get uri, auth_header
        rescue Exception => timeout_exception
          response.reply "Error: #{timeout_exception}"
          return
        end

        alerts = Hash.new { |h, k| h[k] = 0 }

        master_events = []
        events = JSON.parse resp.body
        # alerts = process_event(events, alerts)
        events_count = events['events'].count
        Lita.logger.debug "events_count = #{events_count}"

        events['events'].each do |eve|
          master_events.push eve['event']['json']['message']
        end

        while events['next'] do
          Lita.logger.debug "Getting next #{events['next']}"
          resp = get_events_from_loggly(auth_header, events)
          events = JSON.parse resp.body
          events['events'].each do |eve|
            master_events.push eve['event']['json']['message']
          end
          # alerts = process_event(events, alerts)
        end

        Lita.logger.debug "#{events_count} events"
        response.reply "#{events_count} events"
        Lita.logger.debug "#{master_events.count} events"
        response.reply "#{master_events.count} events"

        url_list = []
        master_events.each do |message|
          if md = /,\s+req_url=([^,]+),/.match(message)
            Lita.logger.debug md.captures[0]
            url_list.push md.captures[0]
          end
        end

        url_list.each do |url|
          alerts[url] += 1
        end

        file = File.open("oneoff_endeca_report.csv", "w")
        # replies = ''
        alerts = alerts.sort_by { |_k, v| -v }
        alerts.each do |key, count|
          # Lita.logger.debug "Counted #{count}: #{key}"
          # replies += "Counted #{count}: #{key}\n"
          file.write("#{count},#{key}\n")
        end

        file.close
        response.reply "oneoff_endeca_report.csv created."
      end

      def get_events_from_loggly(auth_header, events)
        # TODO: Implement catch/retry on 502s.
        RestClient.get events['next'], auth_header
      end

      # So, anyone want to abuse Loggly into producing a report that gives these numbers but per hour?
      #
      # ```Calls from MT to BE;  Last 3 hrs (2017-11-24T12:23:23.071-08:00 to 2017-11-24T15:23:23.071-08:00)
      # 3.3 MM total calls to BE  (Loggly: `"translation--prod" "About to make "`)
      # 2.7 MM total calls (80% of total BE calls) from MT to Endeca (Loggly: `"translation--prod" "About to make to Endeca"`)
      # 2.2 (80%) have nrpp URL param
      # nrpp=9 :   995,513 (Loggly: `"translation--prod" "About to make to Endeca" "'Nrpp': 9"`)
      # nrpp=6 :    24,224 (Loggly: `"translation--prod" "About to make to Endeca" "'Nrpp': 6"`)
      # nrpp=4 : 1,085,459 (Loggly: `"translation--prod" "About to make to Endeca" "'Nrpp': 4"`)```
      def hourly_oneoff(response)
        auth_header = { 'Authorization': "bearer #{config.api_key}" }

        query = '"translation--prod" "About to make to Endeca"'
        uri = "http://lululemon.loggly.com/apiv2/search?q=#{CGI::escape query}&from=-1h&until=now"

        rsid_response = call_loggly(uri)
        rsid = rsid_response['rsid']['id']

        events = call_loggly("http://lululemon.loggly.com/apiv2/events?rsid=#{rsid}")
        Lita.logger.debug "Total requests count: #{events['total_events']}"
        response.reply events['total_events'].to_s + ' Events'

        # sample_query = "/iterate?q=#{CGI::escape query}&from=-3h&until=-2hsize=1000"
        # uri = "#{config.base_uri}#{sample_query}"
        # Lita.logger.debug uri
        #
        # begin
        #   resp = RestClient.get uri, auth_header
        # rescue Exception => timeout_exception
        #   response.reply "Error: #{timeout_exception}"
        #   return
        # end

        # alerts = Hash.new { |h, k| h[k] = 0 }
        #
        # master_events = []
        # events = JSON.parse resp.body
        # # alerts = process_event(events, alerts)
        # events_count = events['events'].count
        # Lita.logger.debug "events_count = #{events_count}"

        # events['events'].each do |eve|
        #   master_events.push eve['event']['json']['message']
        # end
        #
        # while events['next'] do
        #   Lita.logger.debug "Getting next #{events['next']}"
        #   resp = RestClient.get events['next'], auth_header
        #   events = JSON.parse resp.body
        #   events['events'].each do |eve|
        #     master_events.push eve['event']['json']['message']
        #   end
        #   # alerts = process_event(events, alerts)
        # end

        # Lita.logger.debug "#{events_count} events"
        # response.reply "#{events_count} events"
        # Lita.logger.debug "#{master_events.count} events"
        # response.reply "#{master_events.count} events"

        # url_list = []
        # master_events.each do |message|
        # end

        # response.reply "#{master_events.count} events counted"
      end

      def rollup_events(events)
        event_counts = {}
        events['events'].each do |event|
          # Let's see what we've got.
          Lita.logger.debug event
          msg = JSON.parse(event['logmsg'])
          if event.key? 'event' and event['event'].key? 'json' and event['event']['json'].key? 'req_url'
            url = event['event']['json']['req_url']
            # strip off QPs
            if url.include? '?'
              url = url[0..url.index('?')-1]
            end
            # Add url or increment count for this url
            if event_counts.key?(url)
              event_counts[url] = event_counts[url]+1
            else
              event_counts[url] = 1
            end
          end
        end
        event_counts
      end

      # hashes have count/url.
      # merge hashes and update the count if URLs match
      def merge_hash_with_counts(hash_total, hash_event)
        hash_event.each do |key, value|
          if hash_total.key?(key)
            hash_total[key] = hash_event[key] + hash_total[key]
          else
            hash_total[key] = hash_event[key]
          end
        end
        hash_total
      end

      def process_event(events, alerts)
        events['events'].each do |event|
          # Let's a see a what a we a gotta
          Lita.logger.debug event
          if event.key? 'event' and event['event'].key? 'json' and event['event']['json'].key? 'fault'
            fault_name = event['event']['json']['fault']
            alerts[fault_name] += 1
          end
        end
        alerts
      end

      Lita.register_handler(self)
    end
  end
end
