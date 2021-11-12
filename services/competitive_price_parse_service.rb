# frozen_string_literal: true

require 'active_support'
require 'json'
require_relative 'base_service'
require_relative 'fetch_services/fetch_competitive_pricing_data_service'
require_relative '../modules/services_helper_methods'

# CompetitivePriceParseService with 64 threads
class CompetitivePriceParseService < BaseService
  include ServicesHelperMethods
  def initialize(entries, users)
    super()
    return if entries.blank?

    initialize_defined_variables(THREAD_COUNT, entries)
    initialize_semaphores
    @entries = entries.reject { |entry| entry[:status].include?('error') }
    @users = users
    @_cached_records = Array.new(@entries)
    @user_count = @users.count
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

  def send_fetch_and_process_request(user, retries, current_entries)
    data_array = FetchCompetitivePricingDataService.new(user, @users, current_entries).fetch_and_process_data(10)
    merge_same_asin_hash(
      @result_array,
      data_array.flatten
    )
  rescue StandardError => e
    exception_printer(e)
    retries += 1
    retry if retries <= 3
  end

  def remaining_data
    @search_key_semaphore.synchronize do
      puts "Remaining: FetchCompetitivePricingDataService #{@_cached_records.count}"
      @_cached_records.blank? ? false : @_cached_records.shift(5)
    end
  end
end
