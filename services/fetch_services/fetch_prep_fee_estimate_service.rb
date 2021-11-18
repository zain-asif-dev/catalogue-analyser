# frozen_string_literal: true

require 'active_support'
require 'dotenv/load'
require 'json'
require 'peddler'

# FetchPrepFeeEstimateService
class FetchPrepFeeEstimateService
  def initialize(user, users, list)
    initialize_common(user, users)
    @list = list
  end

  def parse_data
    response_array = []
    response = @client.get_prep_instructions_for_asin('US', @list.reject(&:blank?)).parse
    prep_list = [response['ASINPrepInstructionsList']].flatten

    prep_list.each do |prep_item|
      next if prep_item.blank?

      asins_information = [prep_item['ASINPrepInstructions']].flatten
      asins_information.each do |asin_information|
        instructions = [asin_information['PrepInstructionList']].flatten
        instruction_str ||= ''

        instructions.each do |instruction|
          instruction_str += "#{[instruction['PrepInstruction']].flatten.join(',')}," if instruction.present?
        end

        response_array << { asin: asin_information['ASIN'], prep_instructions: instruction_str.chomp(',') }
      end
    end
    response_array
  end
end