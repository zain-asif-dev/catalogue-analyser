# frozen_string_literal: true

# Module to define methods to enhance reusability of common methods of all services
module ServicesHelperMethods
  def initialize_common(entries, thread_count, users = nil)
    @entries = entries.reject { |entry| entry[:status]&.include?('error') }
    return if entries.blank?

    initialize_defined_variables(thread_count, entries)
    @search_key_semaphore = Mutex.new
    @search_user_semaphore = Mutex.new
    @data_set_semaphore = Mutex.new
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

  def available_user
    @search_user_semaphore.synchronize do
      agent = @users[user_index]
      agent.blank? ? @users.sample : agent
    end
  end

  def start
    @threads = []
    (0...@thread_size).each do
      @threads << Thread.new { do_scrap }
    end
    @threads.each(&:join)
    @result_array&.flatten
  rescue StandardError => e
    exception_printer(e)
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
