module ScopedSearch
  
  module ClassMethods
  
    def self.extended(base)
      require 'scoped_search/reg_tokens'
      require 'scoped_search/query_language_parser'
    end
  
    # Creates a named scope in the class it was called upon
    def searchable_on(*fields)
      self.cattr_accessor :scoped_search_fields
      self.scoped_search_fields = fields
      self.named_scope :search_for, lambda { |keywords| self.build_scoped_search_conditions(keywords) }
    end
  
    # Build a hash that is used for the named_scope search_for.
    # This function will split the search_string into keywords, and search for all the keywords
    # in the fields that were provided to searchable_on
    def build_scoped_search_conditions(search_string)
      if search_string.nil? || search_string.strip.blank?
        return { :conditions => nil }
      else
        conditions = []
        query_params = {}
        
        QueryLanguageParser.parse(search_string).each_with_index do |search_condition, index|
          keyword_name = "keyword_#{index}".to_sym
          query_params[keyword_name] = "%#{search_condition.first}%" 
        
          # a keyword may be found in any of the provided fields, so join the conitions with OR
          if search_condition.length == 2 && search_condition.last == :not
            keyword_conditions = self.scoped_search_fields.map do |field| 
              field_name = connection.quote_table_name(table_name) + "." + connection.quote_column_name(field)
              "(#{field_name} NOT LIKE :#{keyword_name.to_s} OR #{field_name} IS NULL)"
            end
            conditions << "(#{keyword_conditions.join(' AND ')})" 
          elsif search_condition.length == 2 && search_condition.last == :or
            word1, word2 = query_params[keyword_name].split(' OR ')
            
            query_params.delete(keyword_name)
            keyword_name_a = "#{keyword_name.to_s}a".to_sym
            keyword_name_b = "#{keyword_name.to_s}b".to_sym
            query_params[keyword_name_a] = word1
            query_params[keyword_name_b] = word2
            
            keyword_conditions = self.scoped_search_fields.map do |field| 
              field_name = connection.quote_table_name(table_name) + "." + connection.quote_column_name(field)
              "(#{field_name} LIKE :#{keyword_name_a.to_s} OR #{field_name} LIKE :#{keyword_name_b.to_s})"
            end
            conditions << "(#{keyword_conditions.join(' OR ')})"            
          else
            keyword_conditions = self.scoped_search_fields.map do |field| 
              field_name = connection.quote_table_name(table_name) + "." + connection.quote_column_name(field)
              "#{field_name} LIKE :#{keyword_name.to_s}"
            end
            conditions << "(#{keyword_conditions.join(' OR ')})"
          end       
        end
              
        # all keywords must be matched, so join the conditions with AND
        return { :conditions => [conditions.join(' AND '), query_params] }
      end
    end
  end
end

ActiveRecord::Base.send(:extend, ScopedSearch::ClassMethods)