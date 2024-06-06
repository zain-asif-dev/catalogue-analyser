# frozen_string_literal: true

require 'active_support'
require 'dotenv/load'
require 'json'
require 'peddler'
require_relative '../../modules/fetch_services_helper_methods'

# FetchPrepFeeEstimateService
class FetchPrepFeeEstimateService
  include FetchServicesHelperMethods
  def initialize(user, users, list)
    initialize_common(user, users)
    @list = list.map { |entry| entry[:asin] }
    update_user_and_client
    @client = set_client
  end

  def parse_data
    response_array = []
    response = fetch_data(response_array)
    prep_list = [response['ASINPrepInstructionsList']]&.flatten

    prep_list.each do |prep_item|
      next if prep_item.blank?

      asins_information = [prep_item['ASINPrepInstructions']]&.flatten
      asins_information.each do |asin_information|
        instructions = [asin_information['PrepInstructionList']]&.flatten
        instruction_str ||= ''

        instructions.each do |instruction|
          instruction_str += "#{[instruction['PrepInstruction']]&.flatten&.join(',')}," if instruction.present?
        end

        response_array << { asin: asin_information['ASIN'], prep_instructions: instruction_str.chomp(',') }
      end
    end
    response_array
  end

  def fetch_data(response_arr)
    response = JSON.parse(get_prep_instructions_for_asin(@list).read_body)
    # @client.get_competitive_pricing_for_asin(ENV['MARKETPLACE_ID'], list_item)
    check_response(response, response_arr)
  end
end
