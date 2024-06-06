# frozen_string_literal: true

# Module to define methods to enhance reusability of common methods of all services
module ServicesHelperMethods
  def initialize_common(entries, thread_count, users = nil)
    # Filter out entries with 'error' status
    @entries = entries.reject { |entry| entry[:status]&.include?('error') }
    puts @entries.count
    return if @entries.blank?

    initialize_defined_variables(thread_count, @entries)
    
    # Initialize semaphores for thread safety
    @search_key_semaphore = Mutex.new
    @search_user_semaphore = Mutex.new
    @data_set_semaphore = Mutex.new

    # Initialize users if provided
    initialize_users(users) unless users.nil?

    # Cache records
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
      # Ensure @users is initialized and not empty
      if @users && @users.any?
        agent = @users[@current_user_index]
        agent.blank? ? @users.sample : agent
      else
        nil
      end
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

      result_hash = result_array.find { |result| result[:asin] == data_hash[:asin] }
      result_hash.merge!(data_hash) if result_hash
    end
  end

  def exception_printer(error)
    puts error.message
    puts error.backtrace.join("\n")
    puts '*********** Crashed ************'
  end
end
