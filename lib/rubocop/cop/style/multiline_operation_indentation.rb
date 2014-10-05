# encoding: utf-8

module RuboCop
  module Cop
    module Style
      # This cops checks the indentation of the right hand side operand in
      # binary operations that span more than one line.
      #
      # @example
      #   # bad
      #   if a +
      #   b
      #     something
      #   end
      class MultilineOperationIndentation < Cop
        include ConfigurableEnforcedStyle
        include AutocorrectAlignment

        def on_and(node)
          check_and_or(node)
        end

        def on_or(node)
          check_and_or(node)
        end

        def on_send(node)
          receiver, _method_name, *_args = *node
          return unless receiver

          rhs = right_hand_side(node)
          range = offending_range(node, receiver, rhs, style)
          check(range, node, receiver, rhs)
        end

        private

        def check_and_or(node)
          lhs, rhs = *node
          range = offending_range(node, lhs, rhs.loc.expression, style)
          check(range, node, lhs, rhs.loc.expression)
        end

        def check(range, node, lhs, rhs)
          if range
            incorrect_style_detected(range, node, lhs, rhs)
          else
            correct_style_detected
          end
        end

        def incorrect_style_detected(range, node, lhs, rhs)
          add_offense(range, range, message(node, lhs, rhs)) do
            unless offending_range(node, lhs, rhs, alternative_style)
              opposite_style_detected
            end
          end
        end

        def offending_range(node, lhs, rhs, given_style)
          return false unless begins_its_line?(rhs)
          return false if lhs.loc.line == rhs.line # Needed for unary op.
          return false if not_for_this_cop?(node)

          correct_column = if should_align?(node, given_style)
                             lhs.loc.column
                           else
                             indentation(lhs) + correct_indentation(node)
                           end
          @column_delta = correct_column - rhs.column
          rhs if @column_delta != 0
        end

        def message(node, lhs, rhs)
          what = operation_description(node)
          if should_align?(node, style)
            "Align the operands of #{what} spanning multiple lines."
          else
            used_indentation = rhs.column - indentation(lhs)
            "Use #{correct_indentation(node)} (not #{used_indentation}) " \
              "spaces for indenting #{what} spanning multiple lines."
          end
        end

        def indentation(node)
          node.loc.expression.source_line =~ /\S/
        end

        def operation_description(node)
          ancestor = kw_node_with_special_indentation(node)
          if ancestor
            kw = ancestor.loc.keyword.source
            kind = kw == 'for' ? 'collection' : 'condition'
            article = kw =~ /^[iu]/ ? 'an' : 'a'
            "a #{kind} in #{article} `#{kw}` statement"
          else
            'an expression' + (assignment?(node) ? ' in an assignment' : '')
          end
        end

        def right_hand_side(send_node)
          _, method_name, *args = *send_node
          if operator?(method_name) && args.any?
            args.first.loc.expression
          elsif send_node.loc.dot &&
                send_node.loc.dot.line == send_node.loc.selector.line
            send_node.loc.dot.join(send_node.loc.selector)
          else
            send_node.loc.selector
          end
        end

        def correct_indentation(node)
          multiplier = kw_node_with_special_indentation(node) ? 2 : 1
          IndentationWidth::CORRECT_INDENTATION * multiplier
        end

        def should_align?(node, given_style)
          given_style == :aligned && (kw_node_with_special_indentation(node) ||
                                      assignment?(node))
        end

        def kw_node_with_special_indentation(node)
          node.each_ancestor.find do |a|
            next unless a.loc.respond_to?(:keyword)

            case a.type
            when :if, :while, :until
              condition, = *a
              within?(node, condition)
            when :for
              _, collection, _ = *a
              within?(node, collection)
            end
          end
        end

        def within?(inner, outer)
          o, i = outer.loc.expression, inner.loc.expression
          i.begin_pos >= o.begin_pos && i.end_pos <= o.end_pos
        end

        def assignment?(node)
          node.each_ancestor { |a| return true if ASGN_NODES.include?(a.type) }
          false
        end

        def not_for_this_cop?(node)
          node.each_ancestor.find do |ancestor|
            grouped_expression?(ancestor) ||
              inside_arg_list_parentheses?(node, ancestor)
          end
        end

        def grouped_expression?(node)
          node.type == :begin && node.loc.respond_to?(:begin) && node.loc.begin
        end

        def inside_arg_list_parentheses?(node, ancestor)
          a = ancestor.loc
          return false unless ancestor.type == :send && a.begin &&
                              a.begin.is?('(')
          n = node.loc.expression
          n.begin_pos > a.begin.begin_pos && n.end_pos < a.end.end_pos
        end
      end
    end
  end
end
