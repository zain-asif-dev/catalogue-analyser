# frozen_string_literal: true

require 'axlsx'
require 'dotenv/load'
require 'json'
require 'aws-sdk-s3'
require 'fileutils'
require 'active_support'

# GenerateFileOutputService
class GenerateFileOutputService
  LABELING_CHARGES = 0.34
  BUBBLE_CHARGES = 0.80
  POLYBAG_CHARGES = 0.46
  BOX_CHARGES = 0
  TAPING_CHARGES = 0.22
  QUANTITY_IN_CASE_CHARGES = 0.46
  ALPHABETS = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O',
               'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', 'AA', 'AB', 'AC', 'AD',
               'AE', 'AF', 'AG', 'AH', 'AI', 'AJ', 'AK', 'AL', 'AM', 'AN', 'AO', 'AP', 'AQ', 'AR',
               'AS', 'AT', 'AU', 'AV', 'AW', 'AX', 'AY', 'AZ']

  def initialize(vendor_asins)
    @vendor_asins = vendor_asins
    @columns_not_required = ENV['columns_not_required']
  end

  def generate_catalog_output
    directory_path = 'output_files'
    FileUtils.mkdir_p directory_path
    headers = ['ASIN', 'AMAZON UPC', 'Cost', 'Bundle Quantity', 'Bundle Cost', 'Case Quantity',
               'ESTIMATED amazon bundle cost', 'ESTIMATED amazon bundle quantity', 'ITEM NUMBER',
               'Supplier Product Description', 'Amazon Product Description', 'Estimated Sales Monthly', 'Sales Rank',
               'BuyBox Price', 'Net Profit $USD', 'ROI',
               '# Total Offers', 'If Amazon is Selling', 'FBA Fee',
               'Reference Offer', 'Amazon Offers', 'Storage Fee', 'Complete FBA Fee',
               'Variable Closing Fee', 'Comm. Pct',
               'Comm. Fee', 'Inbound Shipping', 'Prep Fee', 'FBA Sellers',
               '# FBM Offers', 'Lowest FBA Offer',
               'Lowest MFN Offer', 'IsBuybox FBA', 'Product Type', 'Weight', 'Length', 'Width', 'Height',
               'Package Weight',
               'Package Length', 'Package Width', 'Package Height', 'SIZE TIER', 'Brand']

    @columns_not_required.to_s.split(',').map { |value| headers.delete(value) }
    mapper_hash = {}
    headers.each_with_index { |value, index| mapper_hash[ALPHABETS[index]] = value }

    # blue_header_indexes = [0, 1, 2, 3, 5, 6, 7, 8, 9, 13, 14]
    blue_header_indexes = ['ASIN', 'AMAZON UPC', 'Cost', 'Bundle Quantity', 'Case Quantity', 'ESTIMATED amazon bundle cost',
                           'ESTIMATED amazon bundle quantity', 'ITEM NUMBER', 'Supplier Product Description', 'BuyBox Price', 'Net Profit $USD']
    # yellow_header_indexes = [4, 10, 11, 12, 16]
    yellow_header_indexes = ['Bundle Cost', 'Amazon Product Description', 'Estimated Sales Monthly', 'Sales Rank', '# Total Offers']

    xlsx_package = Axlsx::Package.new
    xlsx_package.use_autowidth = true
    work_book = xlsx_package.workbook

    blue_header_style = work_book.styles.add_style({ alignment: { horizontal: :center, vertical: :top, wrap_text: true }, bg_color: "99CDFF"})
    yellow_header_style = work_book.styles.add_style({ alignment: { horizontal: :center, vertical: :top, wrap_text: true }, bg_color: "FFFF09"})
    white_header_style = work_book.styles.add_style({ alignment: { horizontal: :center, vertical: :top, wrap_text: true }})

    row_style                  = work_book.styles.add_style({alignment: {horizontal: :center, vertical: :top}})
    green_row_style            = work_book.styles.add_style({ alignment: { horizontal: :center, vertical: :top }, bg_color: 'BFF8CE' })
    green_cell_with_percentage = work_book.styles.add_style({ alignment: { horizontal: :center, vertical: :top }, bg_color: 'BFF8CE' })
    red_row_style              = work_book.styles.add_style({ alignment: { horizontal: :center, vertical: :top }, bg_color: 'F9C9C5' })
    extreme_red_row_style      = work_book.styles.add_style({ alignment: { horizontal: :center, vertical: :top }, bg_color: 'FE0000' })
    red_cell_with_percentage   = work_book.styles.add_style({ alignment: { horizontal: :center, vertical: :top }, bg_color: 'F9C9C5' })
    default_row_style          = work_book.styles.add_style({ alignment: { horizontal: :center, vertical: :top } })
    red_cell_style             = work_book.styles.add_style({ alignment: { horizontal: :center, vertical: :top }, fg_color: 'E80F00', bg_color: 'BFF8CE' })

    fba_seller_index = [26]
    amazon_selling_index = 17
    percentage_cells = [15]

    red_background_cells = [0, 1, 3, 8, 9, 12, 18]
    red_text_cells = [12, fba_seller_index]&.flatten
    yellow_text_cells = [12]
    always_green_cells = [12]
    roi_cell = 14

    work_book.add_worksheet(name: 'Catalog Output') do |sheet|
      work_book.styles.fonts.first.name = 'Calibri'
      header_row = sheet.add_row headers, height: 100, b: true, sz: 10, a: true
      sheet.sheet_view.pane do |pane|
        pane.top_left_cell = 'A2'
        pane.state = :frozen_split
        pane.y_split = 1
        pane.x_split = 0
        pane.active_pane = :bottom_right
      end

      header_row.cells.each_with_index do |header_cell, header_cell_index|
        header_cell.style = if blue_header_indexes.include? header_cell.value
                              blue_header_style
                            elsif yellow_header_indexes.include? header_cell.value
                              yellow_header_style
                            else
                              white_header_style
                            end
      end

      if @vendor_asins&.flatten&.count&.zero?
        puts '--------------There  is an issue with the File or the Vendor-------------------'
        return -1
      end

      @vendor_asins&.flatten&.each_with_index do |item, index|
        row_index_for_formula = index + 2
        bbp = mapper_hash.key('BuyBox Price')
        cost = mapper_hash.key('Cost')
        bundle_quantity = mapper_hash.key('Bundle Quantity')
        fba_fee = mapper_hash.key('FBA Fee')
        commission_fee = mapper_hash.key('Comm. Fee')
        commission_pct = mapper_hash.key('Comm. Pct')
        storage_fee = mapper_hash.key('Storage Fee')
        inbound_shipping = mapper_hash.key('Inbound Shipping')
        estimated_amz_bundle_quantity = mapper_hash.key('ESTIMATED amazon bundle quantity')

        formula_string = "=(#{bbp}#{row_index_for_formula}-#{cost}#{row_index_for_formula}*#{bundle_quantity}#{row_index_for_formula}-#{fba_fee}#{row_index_for_formula}-#{commission_fee}#{row_index_for_formula}-#{storage_fee}#{row_index_for_formula}-#{inbound_shipping}#{row_index_for_formula})"
        roi_formula = "#{formula_string}/(#{cost}#{row_index_for_formula}*#{bundle_quantity}#{row_index_for_formula}) * 100"
        bundle_cost_formula = "=#{cost}#{row_index_for_formula}*#{bundle_quantity}#{row_index_for_formula}"
        amazon_pack_cost_formula = "=#{cost}#{row_index_for_formula}*#{estimated_amz_bundle_quantity}#{row_index_for_formula}"
        commission_fee_formula = "=(#{commission_pct}#{row_index_for_formula}*#{bbp}#{row_index_for_formula})"
        item_profit = excel_profit(item)
        next if item.blank?

        record = {
          'ASIN': item[:asin],
          'AMAZON UPC': item[:upc],
          'Cost': item[:cost_price].to_f,
          'Bundle Quantity': 1,
          'Bundle Cost': bundle_cost_formula,
          'Case Quantity': (item[:case_quantity] || 1),
          'ESTIMATED amazon bundle cost': amazon_pack_cost_formula,
          'ESTIMATED amazon bundle quantity': item[:packagequantity].to_i,
          'ITEM NUMBER': item[:sku],
          'Supplier Product Description': remove_special_characters(item[:item_description]),
          'Amazon Product Description': remove_special_characters(title(item)),
          'Estimated Sales Monthly': item[:salespermonth] || 0,
          'Sales Rank': item[:salesrank],
          'BuyBox Price': buyboxprice(item),
          'Net Profit $USD': formula_string,
          'ROI': roi_formula,
          '# Total Offers': item[:totaloffers],
          'If Amazon is Selling': item[:amazon_selling] ? 'AMZ' : '-',
          'FBA Fee': item[:fba_fee],
          'Reference Offer': item[:referenceoffer],
          'Amazon Offers': item[:fbaoffers],
          'Storage Fee': current_storage_fee(item),
          'Complete FBA Fee': complete_fba_fee(item),
          'Variable Closing Fee': item[:variableclosingfee],
          'Comm. Pct': "#{item[:commissionpct].presence || 15}%",
          'Comm. Fee': commission_fee_formula,
          'Inbound Shipping': ENV['inbound_fee'],
          'Prep Fee': calculate_prep_fee(item),
          'FBA Sellers': item[:fbaoffers],
          '# FBM Offers': item[:fbmoffers],
          'Lowest FBA Offer': item[:lowestfbaoffer],
          'Lowest MFN Offer': item[:lowestfbmoffer],
          'IsBuybox FBA': buy_box_seller(item),
          'Product Type': item[:product_type] || '',
          'Weight': item[:weight],
          'Length': item[:length],
          'Width': item[:width],
          'Height': item[:height],
          'Package Weight': item[:packageweight],
          'Package Length': item[:packagelength],
          'Package Width': item[:packagewidth],
          'Package Height': item[:packageheight],
          'SIZE TIER': item[:size_tier],
          'Brand': item[:brand]
        }

        requried_to_remove = @columns_not_required.to_s.split(',')&.map(&:to_sym)
        row = sheet.add_row record.except(*requried_to_remove).values

        if item_profit.zero?
          row.style = default_row_style
        else
          row.style = item_profit.negative? ? red_row_style : green_row_style
        end
        sheet.column_widths 12, 12, 10, 10, 10, 10, 10, 10, 10, 30, 30, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10,10, 10, 10, 10, 10, 10, 10, 15, 10, 10, 10, 10, 10, 10, 10
        row.cells.each_with_index do |cell, cell_index|
          cell.type = :string if red_background_cells.include?(cell_index)
          if always_green_cells.include?(cell_index)
            cell.style = green_row_style
          else
            if fba_seller_index.include?(cell_index)
              cell.style = red_cell_style
            elsif cell.value == 'AMZ'
              cell.style = extreme_red_row_style
            elsif percentage_cells.include?(cell_index)
              cell.style = item_profit.negative? ? red_cell_with_percentage : green_cell_with_percentage
            else
              cell.style = red_cell_style if item_profit.negative? && red_text_cells.include?(cell_index)
            end
          end
        end
      end
    end

    output_file_name = generate_file_name
    s3_object = Aws::S3::Resource.new.bucket(ENV['AWS_OUTPUT_BUCKET_NAME']).put_object({ key: output_file_name, body: xlsx_package.to_stream.read, acl: 'public-read'})
    puts "-----------------------------#{s3_object.public_url}"

    [output_file_name, s3_object.public_url]
  end

  def title(vendoritem)
    title = vendoritem[:name]
    title.presence || 'Missing Name'
  end

  def generate_file_name
    "#{ENV['FILE_NAME'].gsub('.csv', '')}-#{ENV['FILE_ID']}-#{Time.now.to_datetime.strftime('%d%m%Y')}.xlsx"
  end

  def buy_box_seller(vendorasin)
    vendorasin[:isbuyboxfba] ? 'FBA' : 'FBM'
  end

  def remove_special_characters(str)
    str.to_s.gsub(/[^0-9A-Za-z]/, ' ')[0...200]
  end

  def excel_profit(vendoritem)
    (
      buyboxprice(vendoritem).to_f -
      vendoritem[:cost_price].to_f *
      vendoritem[:packcount].to_i -
      vendoritem[:fba_fee].to_f -
      vendoritem[:commissiionfee].to_f
    ).to_f.round(2)
  end

  def calculate_prep_fee(vendorasin)
    fee = 0.0
    return fee if vendorasin[:prep_instructions].nil?

    fee += LABELING_CHARGES if vendorasin[:prep_instructions].downcase.include?('Labeling'.downcase)
    fee += BUBBLE_CHARGES if vendorasin[:prep_instructions].downcase.include?('Bubble'.downcase)
    fee += POLYBAG_CHARGES if vendorasin[:prep_instructions].downcase.include?('Polybag'.downcase)
    fee += BOX_CHARGES if vendorasin[:prep_instructions].downcase.include?('Box'.downcase)
    fee += TAPING_CHARGES if vendorasin[:prep_instructions].downcase.include?('Taping'.downcase)
    fee += QUANTITY_IN_CASE_CHARGES if vendorasin[:packagequantity] > 1
    fee
  end

  def buyboxprice(vendoritem)
    return vendoritem[:buyboxprice].to_f if vendoritem[:buyboxprice].to_f > 0.0

    0
  end

  def complete_fba_fee(vendorasin)
    vendorasin[:fba_fee].to_f + current_storage_fee(vendorasin).to_f
  end

  def current_storage_fee(vendorasin)
    return 0 if vendorasin[:size_tier].nil?

    current_month_index = Date.today.strftime('%m').to_i
    if current_month_index.between?(1, 9)
      fee = vendorasin[:size_tier].downcase.include?('standard') ? (0.69 * cubic_feet(vendorasin)) : (0.48 * cubic_feet(vendorasin))
    else
      fee = vendorasin[:size_tier].downcase.include?('standard') ? (2.40 * cubic_feet(vendorasin)) : (1.20 * cubic_feet(vendorasin))
    end
    fee.round(8)
  end

  def all_dimensions_present?(vendorasin)
    (
      !vendorasin[:packageheight].blank? && !vendorasin[:packagewidth].blank? &&
      !vendorasin[:packagelength].blank? && !vendorasin[:packageweight].blank?
    )
  end

  def cubic_feet(vendorasin)
    return 0 unless all_dimensions_present?(vendorasin)

    (
      (vendorasin[:packagelength].to_f * vendorasin[:packagewidth].to_f * vendorasin[:packageheight].to_f) / 1728
    ).to_f.round(4)
  end

  def rescue_exceptions
    yield
  rescue StandardError => e
    puts "Error: #{e}"
    false
  end
end
