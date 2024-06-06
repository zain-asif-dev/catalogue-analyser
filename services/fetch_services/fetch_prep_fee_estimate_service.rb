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
    # @client = set_client
  end

  def parse_data
    response_array = []
    response = fetch_data(response_array)
    prep_list = [response.dig(0, 'payload', 'ASINPrepInstructionsList')]&.flatten

    prep_list.each do |prep_item|
      next if prep_item.blank?

      instructions = [prep_item['PrepInstructionList']]&.flatten
      instruction_str ||= ''

      instructions.each do |instruction|
        instruction_str += "#{[instruction['PrepInstruction']]&.flatten&.join(',')}," if instruction.present?
      end
      response_array << { asin: prep_item['ASIN'], prep_instructions: instruction_str.chomp(','),
                          barcode_instruction: prep_item['BarcodeInstruction'], prep_guidance: prep_item['PrepGuidance'] }
    end
    response_array
  end

  def fetch_data(response_arr)
    response = JSON.parse(get_prep_instrcutions_by_asin(@list).read_body)
    # @client.get_competitive_pricing_for_asin(ENV['MARKETPLACE_ID'], list_item)
    check_response(response, response_arr)
  end
end
