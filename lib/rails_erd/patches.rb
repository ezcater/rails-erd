# frozen_string_literal: true

module RailsERD
  module Patches
    module HighlightPatterns
      def self.apply_monkey_patch!
        RailsERD::Diagram::Graphviz::Simple.prepend(Patch)
      end

      module Patch
        def table_style(entity, attributes)
          super.tap do |style|
            attributes.each do |attribute|
              color = colors(attribute)[:table_color]
              if color != "transparent"
                style[:bgcolor] = color
                break
              end
            end
          end
        end

        def row_style(entity, attribute)
          super.tap do |style|
            style[:bgcolor] = colors(attribute)[:row_color]
          end
        end

        private

        def colors(attribute)
          color_rules = JSON.parse ENV.fetch("RAILS_ERD_COLORS", "{}")
          # [
          #  {
          #   table_color: "#RRGGBB", tables with a matching row get this color
          #   row_color: "#RRGGBB",   rows that match any term will have this color
          #   name_starts_with: %w(terms in list must match start of column name),
          #   name_equals: %w(terms in this list match exact column name),
          #   name_ends_with: %w(terms in this list match exact end of column name),
          #   name_includes: %w(terms in this list match if anywhere in column name),
          #  }
          # ]

          color_rules.each do |name_in: [], name_starts_with: [], name_ends_with: [], name_includes: [], **colors|
            next unless name_in.any? { |str| attribute.name == str } ||
              name_includes.any?    { |str| attribute.name.include?(str) } ||
              name_ends_with.any?   { |str| attribute.name.ends_with?(str) } ||
              name_starts_with.any? { |str| attribute.name.starts_with?(str) }

            return colors
          end

          { table_color: "transparent", row_color: "transparent" }
        end
      end
    end

    module CustomClustering
      def self.apply_monkey_patch!
        RailsERD::Domain::Entity.prepend(EntityNamespacePatch)
        RailsERD::Diagram::Graphviz.prepend(ClusterStylePatch)
      end

      module ClusterStylePatch
        def cluster_attributes(entity)
          attrs = case entity.namespace
          when /^gem:/   then { style: "filled", color: "#FFEEEE" }
          when /^pack:/  then { style: "filled", color: "#EEEEFF" }
          when /^owner:/ then { style: "filled", color: "#EEFFEE" }
            # when /^'domain':/ then { style: "filled", color: "Wheat1" }
          else {}
          end

          super.
            merge(margin: 10, fontsize: 30).
            merge(attrs)
        end
      end

      class ClusterName
        def self.code_owners
          @_code_owners ||= if defined?(CodeOwners)
            CodeOwners.file_ownerships
          else
            {}
          end
        end

        def initialize(model_name)
          @model_name = model_name
          loaded = Zeitwerk::Registry.loaders[0].to_unload.assoc(@model_name) # e.g. ["Account", ["/usr/src/app/app/models/account.rb", [Object, :Account]]]
          @filepath = loaded&.dig(1, 0)
          @relpath = @filepath&.gsub "#{Rails.root}/", ""
        end

        def namespace
          @_namespace ||= if @filepath.nil?      then "unknown"
          elsif pack_name        then "pack: #{pack_name}"
          elsif code_owner       then "owner: #{code_owner}"
          elsif gem_name         then "gem: #{gem_name}"
          else default_namespace
          end
        end

        private

        def pack_name
          @filepath&.match(/\/usr\/src\/app\/packs\/(.*?)\//).try(:[], 1)
        end

        def code_owner
          owner = self.class.code_owners.dig(@relpath, :owner)
          owner unless owner == "UNOWNED"
        end

        def gem_name
          @filepath&.match(/\/usr\/local\/bundle\/gems\/(.*?)\/.*/).try(:[], 1)
        end

        def default_namespace
          "NO-PACK, NO-OWNER"
        end
      end

      module EntityNamespacePatch
        def namespace
          ClusterName.new(name).namespace
        end
      end
    end
  end
end
