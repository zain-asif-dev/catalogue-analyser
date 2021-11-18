# frozen_string_literal: true

# Module to define methods to enhance reusability of common methods of all services
module ServicesHelperMethods
  def initialize_common(entries, thread_count, users = nil)
    @entries = entries.reject { |entry| entry[:status].include?('error') }
    return if entries.blank?

    initialize_defined_variables(thread_count, entries)
    initialize_semaphores
    initialize_users(users) unless users.nil?
    @_cached_records = Array.new(@entries.to_a)
  end

  def initialize_users(users)
    @users = users
    @user_count = @users.count
  end

  def initialize_defined_variables(thread_size, result_array = [])
    @thread_size = thread_size
    @result_array = result_array
    @current_user_index = 0
  end

  def initialize_semaphores
    @search_key_semaphore = Mutex.new
    @search_user_semaphore = Mutex.new
    @data_set_semaphore = Mutex.new
  end

  def available_user
    @search_user_semaphore.synchronize do
      agent = @users[user_index]
      agent.blank? ? @users.sample : agent
    end
  end

  def start
    # if @_cached_records.blank?
    #   @file_progress =  @file_progress + 10
    #   #puts "file_progress-----------------#{@file_progress}--------------------"
    #   message= update_file_progress(@file["id"], @file_progress)
    #   #puts "-------------------#{message}-----------------------"
    #   return @file_progress
    # end

    @threads = []
    (0...@thread_size).each do
      @threads << Thread.new { do_scrap }
    end
    @threads.each(&:join)
    @result_array.flatten
    # SaveDataSetForEntriesService.new({"FetchCompetitivePricingDataService" => @data_set.flatten}, @entries).map_data
    # message = update_service_time_after_processed(@file["id"], "competitive_last_processed_at")
    # puts "-------------------#{message}-----------------------"
    # @file_progress =  @file_progress + 10
    # puts "file_progress-----------------#{@file_progress}--------------------"
    # message= update_file_progress(@file["id"], @file_progress)
    # puts "-------------------#{message}-----------------------"
    # @file_progress
  rescue StandardError => e
    exception_printer(e)
    # error_message = "CompetitivePriceParseService----------#{e.message.first(180)}"
    # update_error_message_in_file(@file['id'], error_message)
    # ExceptionNotifier.notify_exception(
    #   e,
    #   data: { file: file, error: e.message.first(200)}
    # )
    # message = update_service_time_after_processed(@file['id'], 'competitive_last_processed_at')
    # puts "-------------------#{message}-----------------------"
  end

  def do_scrap
    user = available_user
    while (current_entries = remaining_data)
      next if current_entries.blank?

      retries = 0
      send_fetch_and_process_request(user, retries, current_entries)
    end
    Thread.exit
  end

  def merge_same_asin_hash(result_array, data_array)
    data_array.each do |data_hash|
      next if data_hash.nil? || data_hash.empty?

      result_array.find { |result_hash| result_hash[:asin] == data_hash[:asin] }.merge!(data_hash)
    end
  end

  def exception_printer(error)
    puts error.message
    puts error.backtrace.join("\n")
    puts '*********** Crashed ************'
  end
end
