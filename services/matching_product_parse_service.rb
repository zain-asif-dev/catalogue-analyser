# frozen_string_literal: true

require 'json'
require 'active_support'
require_relative 'base_service'
require_relative 'fetch_services/fetch_matching_product_data_service'
require_relative '../modules/services_helper_methods'

# MatchingProductParseService with 64 threads
class MatchingProductParseService < BaseService
  include ServicesHelperMethods
  def initialize(entries, users)
    super()
    return if entries.blank?

    initialize_defined_variables(THREAD_COUNT)
    initialize_semaphores
    @entries = entries.reject { |entry| entry['status'] == 'error' }
    @users = users
    @_cached_records = Array.new(@entries.to_a)
    @user_count = @users.count
  end

  def send_fetch_and_process_request(user, retries, current_entries)
    @result_array << FetchMatchingProductDataService.new(user, @users, current_entries).fetch_and_process_data(20)
  rescue StandardError => e
    exception_printer(e)
    retries += 1
    retry if retries <= 3
  end

  def remaining_data
    @search_key_semaphore.synchronize do
      puts "Remaining: FOR MatchingProductParseService #{@_cached_records.count}"
      return false if @_cached_records.blank?

      return @_cached_records.shift(20)
    end
  end
end
