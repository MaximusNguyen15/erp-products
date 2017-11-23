module Erp::Products
  class StockCheck < ApplicationRecord
    validates :code, :adjustment_date, :warehouse_id, :presence => true
    belongs_to :creator, class_name: "Erp::User"
    belongs_to :employee, class_name: "Erp::User"
    
    has_many :stock_check_details, inverse_of: :stock_check, dependent: :destroy
    accepts_nested_attributes_for :stock_check_details, :reject_if => lambda { |a| a[:product_id].blank? || a[:quantity].blank? }, :allow_destroy => true
    if Erp::Core.available?("warehouses")
      belongs_to :warehouse, class_name: "Erp::Warehouses::Warehouse"
      def warehouse_name
        warehouse.present? ? warehouse.name : ''
      end
    end
    after_create  :update_stock_check_status
    
    # display employee name
    def employee_name
      employee.present? ? employee.name : ''
    end
    
    # class const
    STOCK_CHECK_STATUS_DRAFT = 'draft'
    STOCK_CHECK_STATUS_DONE = 'done'
    
    after_save :update_product_cache_stock

    # update product cache stock
    def update_product_cache_stock
			self.stock_check_details.each do |scd|
        scd.update_product_cache_stock
      end
		end
    
    # Generate code
    before_validation :generate_code
    def generate_code
			if !code.present?
				num = StockCheck.where('adjustment_date >= ? AND adjustment_date <= ?', self.adjustment_date.beginning_of_month, self.adjustment_date.end_of_month).count + 1

				self.code = 'KK' + adjustment_date.strftime("%m") + adjustment_date.strftime("%Y").last(2) + "-" + num.to_s.rjust(3, '0')
			end
		end
    
    # Filters
    def self.filter(query, params)
      params = params.to_unsafe_hash
      and_conds = []
      show_archived = false
      
      #filters
      if params["filters"].present?
        params["filters"].each do |ft|
          or_conds = []
          ft[1].each do |cond|
            # in case filter is show archived
            if cond[1]["name"] == 'show_archived'
              show_archived = true
            else
              or_conds << "#{cond[1]["name"]} = '#{cond[1]["value"]}'"
            end
          end
          and_conds << '('+or_conds.join(' OR ')+')' if !or_conds.empty?
        end
      end
      
      # show archived items condition - default: false
      show_archived = false
      
      #filters
      if params["filters"].present?
        params["filters"].each do |ft|
          or_conds = []
          ft[1].each do |cond|
            # in case filter is show archived
            if cond[1]["name"] == 'show_archived'
              # show archived items
              show_archived = true
            else
              or_conds << "#{cond[1]["name"]} = '#{cond[1]["value"]}'"
            end
          end
          and_conds << '('+or_conds.join(' OR ')+')' if !or_conds.empty?
        end
      end
      
      #keywords
      if params["keywords"].present?
        params["keywords"].each do |kw|
          or_conds = []
          kw[1].each do |cond|
            or_conds << "LOWER(#{cond[1]["name"]}) LIKE '%#{cond[1]["value"].downcase.strip}%'"
          end
          and_conds << '('+or_conds.join(' OR ')+')'
        end
      end
      
      # global filter
      global_filter = params[:global_filter]
      
      if global_filter.present?

        # if has period
        if global_filter[:period].present?
          period = Erp::Periods::Period.find(global_filter[:period])
          global_filter[:from_date] = period.from_date
          global_filter[:to_date] = period.to_date
        end

				# filter by order from date
				if global_filter[:from_date].present?
					query = query.where('adjustment_date >= ?', global_filter[:from_date].to_date.beginning_of_day)
				end

				# filter by order to date
				if global_filter[:to_date].present?
					query = query.where('adjustment_date <= ?', global_filter[:to_date].to_date.end_of_day)
				end
				
			end

      # join with users table for search creator
      query = query.joins(:creator)
      
      # showing archived items if show_archived is not true
      query = query.where(archived: false) if show_archived == false
      
      # add conditions to query
      query = query.where(and_conds.join(' AND ')) if !and_conds.empty?
      
      return query
    end
    
    def self.search(params)
      query = self.all
      query = self.filter(query, params)
      
      # order
      if params[:sort_by].present?
        order = params[:sort_by]
        order += " #{params[:sort_direction]}" if params[:sort_direction].present?
        
        query = query.order(order)
      end
      
      return query
    end
    
    # data for dataselect ajax
    def self.dataselect(keyword='')
      query = self.all
      
      if keyword.present?
        keyword = keyword.strip.downcase
        query = query.where('LOWER(name) LIKE ?', "%#{keyword}%")
      end
      
      query = query.limit(8).map{|stock_check| {value: stock_check.id, text: stock_check.code} }
    end
    
    def creator_name
      creator.present? ? creator.name : ''
    end
    
    def archive
			update_attributes(archived: true)
		end
    
    def unarchive
			update_attributes(archived: false)
		end
    
    def self.archive_all
			update_all(archived: true)
		end
    
    def self.unarchive_all
			update_all(archived: false)
		end
    
    # update stock check status
    def update_stock_check_status
      self.update_columns(status: Erp::Products::StockCheck::STOCK_CHECK_STATUS_DRAFT)
    end
     
    # stock check confirm
    def stock_check_confirm
      self.update_columns(status: Erp::Products::StockCheck::STOCK_CHECK_STATUS_DONE)
    end
  end
end
