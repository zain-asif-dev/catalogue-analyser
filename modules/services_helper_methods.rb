# frozen_string_literal: true

# Module to define methods to enhance reusability of common methods of all services
module ServicesHelperMethods
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
