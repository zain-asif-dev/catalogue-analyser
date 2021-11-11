# frozen_string_literal: true

# Module to define methods to enhance reusability of common methods of all services
module ServicesHelperMethods
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

  def exception_printer(error)
    puts error.message
    puts error.backtrace.join("\n")
    puts '*********** Crashed ************'
  end
end
