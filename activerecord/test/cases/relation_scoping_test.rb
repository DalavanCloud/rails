require "cases/helper"
require 'models/post'
require 'models/author'
require 'models/developer'
require 'models/project'
require 'models/comment'
require 'models/category'
require 'models/person'
require 'models/reference'

class RelationScopingTest < ActiveRecord::TestCase
  fixtures :authors, :developers, :projects, :comments, :posts, :developers_projects

  def test_reverse_order
    assert_equal Developer.order("id DESC").to_a.reverse, Developer.order("id DESC").reverse_order
  end

  def test_reverse_order_with_arel_node
    assert_equal Developer.order("id DESC").to_a.reverse, Developer.order(Developer.arel_table[:id].desc).reverse_order
  end

  def test_reverse_order_with_multiple_arel_nodes
    assert_equal Developer.order("id DESC").order("name DESC").to_a.reverse, Developer.order(Developer.arel_table[:id].desc).order(Developer.arel_table[:name].desc).reverse_order
  end

  def test_reverse_order_with_arel_nodes_and_strings
    assert_equal Developer.order("id DESC").order("name DESC").to_a.reverse, Developer.order("id DESC").order(Developer.arel_table[:name].desc).reverse_order
  end

  def test_double_reverse_order_produces_original_order
    assert_equal Developer.order("name DESC"), Developer.order("name DESC").reverse_order.reverse_order
  end

  def test_scoped_find
    Developer.where("name = 'David'").scoping do
      assert_nothing_raised { Developer.find(1) }
    end
  end

  def test_scoped_find_first
    developer = Developer.find(10)
    Developer.where("salary = 100000").scoping do
      assert_equal developer, Developer.order("name").first
    end
  end

  def test_scoped_find_last
    highest_salary = Developer.order("salary DESC").first

    Developer.order("salary").scoping do
      assert_equal highest_salary, Developer.last
    end
  end

  def test_scoped_find_last_preserves_scope
    lowest_salary  = Developer.order("salary ASC").first
    highest_salary = Developer.order("salary DESC").first

    Developer.order("salary").scoping do
      assert_equal highest_salary, Developer.last
      assert_equal lowest_salary, Developer.first
    end
  end

  def test_scoped_find_combines_and_sanitizes_conditions
    Developer.where("salary = 9000").scoping do
      assert_equal developers(:poor_jamis), Developer.where("name = 'Jamis'").first
    end
  end

  def test_scoped_find_all
    Developer.where("name = 'David'").scoping do
      assert_equal [developers(:david)], Developer.all
    end
  end

  def test_scoped_find_select
    Developer.select("id, name").scoping do
      developer = Developer.where("name = 'David'").first
      assert_equal "David", developer.name
      assert !developer.has_attribute?(:salary)
    end
  end

  def test_scope_select_concatenates
    Developer.select("id, name").scoping do
      developer = Developer.select('salary').where("name = 'David'").first
      assert_equal 80000, developer.salary
      assert developer.has_attribute?(:id)
      assert developer.has_attribute?(:name)
      assert developer.has_attribute?(:salary)
    end
  end

  def test_scoped_count
    Developer.where("name = 'David'").scoping do
      assert_equal 1, Developer.count
    end

    Developer.where('salary = 100000').scoping do
      assert_equal 8, Developer.count
      assert_equal 1, Developer.where("name LIKE 'fixture_1%'").count
    end
  end

  def test_scoped_find_include
    # with the include, will retrieve only developers for the given project
    scoped_developers = Developer.includes(:projects).scoping do
      Developer.where('projects.id' => 2).to_a
    end
    assert scoped_developers.include?(developers(:david))
    assert !scoped_developers.include?(developers(:jamis))
    assert_equal 1, scoped_developers.size
  end

  def test_scoped_find_joins
    scoped_developers = Developer.joins('JOIN developers_projects ON id = developer_id').scoping do
      Developer.where('developers_projects.project_id = 2').to_a
    end

    assert scoped_developers.include?(developers(:david))
    assert !scoped_developers.include?(developers(:jamis))
    assert_equal 1, scoped_developers.size
    assert_equal developers(:david).attributes, scoped_developers.first.attributes
  end

  def test_scoped_create_with_where
    new_comment = VerySpecialComment.where(:post_id => 1).scoping do
      VerySpecialComment.create :body => "Wonderful world"
    end

    assert_equal 1, new_comment.post_id
    assert Post.find(1).comments.include?(new_comment)
  end

  def test_scoped_create_with_create_with
    new_comment = VerySpecialComment.create_with(:post_id => 1).scoping do
      VerySpecialComment.create :body => "Wonderful world"
    end

    assert_equal 1, new_comment.post_id
    assert Post.find(1).comments.include?(new_comment)
  end

  def test_scoped_create_with_create_with_has_higher_priority
    new_comment = VerySpecialComment.where(:post_id => 2).create_with(:post_id => 1).scoping do
      VerySpecialComment.create :body => "Wonderful world"
    end

    assert_equal 1, new_comment.post_id
    assert Post.find(1).comments.include?(new_comment)
  end

  def test_ensure_that_method_scoping_is_correctly_restored
    begin
      Developer.where("name = 'Jamis'").scoping do
        raise "an exception"
      end
    rescue
    end

    assert !Developer.all.where_values.include?("name = 'Jamis'")
  end

  def test_default_scope_filters_on_joins
    assert_equal 1, DeveloperFilteredOnJoins.all.count
    assert_equal DeveloperFilteredOnJoins.all.first, developers(:david).becomes(DeveloperFilteredOnJoins)
  end

  def test_update_all_default_scope_filters_on_joins
    DeveloperFilteredOnJoins.update_all(:salary => 65000)
    assert_equal 65000, Developer.find(developers(:david).id).salary

    # has not changed jamis
    assert_not_equal 65000, Developer.find(developers(:jamis).id).salary
  end

  def test_delete_all_default_scope_filters_on_joins
    assert_not_equal [], DeveloperFilteredOnJoins.all

    DeveloperFilteredOnJoins.delete_all()

    assert_equal [], DeveloperFilteredOnJoins.all
    assert_not_equal [], Developer.all
  end
end

class NestedRelationScopingTest < ActiveRecord::TestCase
  fixtures :authors, :developers, :projects, :comments, :posts

  def test_merge_options
    Developer.where('salary = 80000').scoping do
      Developer.limit(10).scoping do
        devs = Developer.all
        assert_match '(salary = 80000)', devs.to_sql
        assert_equal 10, devs.taken
      end
    end
  end

  def test_merge_inner_scope_has_priority
    Developer.limit(5).scoping do
      Developer.limit(10).scoping do
        assert_equal 10, Developer.all.size
      end
    end
  end

  def test_replace_options
    Developer.where(:name => 'David').scoping do
      Developer.unscoped do
        assert_equal 'Jamis', Developer.where(:name => 'Jamis').first[:name]
      end

      assert_equal 'David', Developer.first[:name]
    end
  end

  def test_three_level_nested_exclusive_scoped_find
    Developer.where("name = 'Jamis'").scoping do
      assert_equal 'Jamis', Developer.first.name

      Developer.unscoped.where("name = 'David'") do
        assert_equal 'David', Developer.first.name

        Developer.unscoped.where("name = 'Maiha'") do
          assert_equal nil, Developer.first
        end

        # ensure that scoping is restored
        assert_equal 'David', Developer.first.name
      end

      # ensure that scoping is restored
      assert_equal 'Jamis', Developer.first.name
    end
  end

  def test_nested_scoped_create
    comment = Comment.create_with(:post_id => 1).scoping do
      Comment.create_with(:post_id => 2).scoping do
        Comment.create :body => "Hey guys, nested scopes are broken. Please fix!"
      end
    end

    assert_equal 2, comment.post_id
  end

  def test_nested_exclusive_scope_for_create
    comment = Comment.create_with(:body => "Hey guys, nested scopes are broken. Please fix!").scoping do
      Comment.unscoped.create_with(:post_id => 1).scoping do
        assert Comment.new.body.blank?
        Comment.create :body => "Hey guys"
      end
    end

    assert_equal 1, comment.post_id
    assert_equal 'Hey guys', comment.body
  end
end

class HasManyScopingTest< ActiveRecord::TestCase
  fixtures :comments, :posts, :people, :references

  def setup
    @welcome = Post.find(1)
  end

  def test_forwarding_of_static_methods
    assert_equal 'a comment...', Comment.what_are_you
    assert_equal 'a comment...', @welcome.comments.what_are_you
  end

  def test_forwarding_to_scoped
    assert_equal 4, Comment.search_by_type('Comment').size
    assert_equal 2, @welcome.comments.search_by_type('Comment').size
  end

  def test_nested_scope_finder
    Comment.where('1=0').scoping do
      assert_equal 0, @welcome.comments.count
      assert_equal 'a comment...', @welcome.comments.what_are_you
    end

    Comment.where('1=1').scoping do
      assert_equal 2, @welcome.comments.count
      assert_equal 'a comment...', @welcome.comments.what_are_you
    end
  end

  def test_should_maintain_default_scope_on_associations
    magician = BadReference.find(1)
    assert_equal [magician], people(:michael).bad_references
  end

  def test_should_default_scope_on_associations_is_overriden_by_association_conditions
    reference = references(:michael_unicyclist).becomes(BadReference)
    assert_equal [reference], people(:michael).fixed_bad_references
  end

  def test_should_maintain_default_scope_on_eager_loaded_associations
    michael = Person.where(:id => people(:michael).id).includes(:bad_references).first
    magician = BadReference.find(1)
    assert_equal [magician], michael.bad_references
  end
end

class HasAndBelongsToManyScopingTest< ActiveRecord::TestCase
  fixtures :posts, :categories, :categories_posts

  def setup
    @welcome = Post.find(1)
  end

  def test_forwarding_of_static_methods
    assert_equal 'a category...', Category.what_are_you
    assert_equal 'a category...', @welcome.categories.what_are_you
  end

  def test_nested_scope_finder
    Category.where('1=0').scoping do
      assert_equal 0, @welcome.categories.count
      assert_equal 'a category...', @welcome.categories.what_are_you
    end

    Category.where('1=1').scoping do
      assert_equal 2, @welcome.categories.count
      assert_equal 'a category...', @welcome.categories.what_are_you
    end
  end
end

class DefaultScopingTest < ActiveRecord::TestCase
  fixtures :developers, :posts

  def test_default_scope
    expected = Developer.all.merge!(:order => 'salary DESC').to_a.collect { |dev| dev.salary }
    received = DeveloperOrderedBySalary.all.collect { |dev| dev.salary }
    assert_equal expected, received
  end

  def test_default_scope_as_class_method
    assert_equal [developers(:david).becomes(ClassMethodDeveloperCalledDavid)], ClassMethodDeveloperCalledDavid.all
  end

  def test_default_scope_as_class_method_referencing_scope
    assert_equal [developers(:david).becomes(ClassMethodReferencingScopeDeveloperCalledDavid)], ClassMethodReferencingScopeDeveloperCalledDavid.all
  end

  def test_default_scope_as_block_referencing_scope
    assert_equal [developers(:david).becomes(LazyBlockReferencingScopeDeveloperCalledDavid)], LazyBlockReferencingScopeDeveloperCalledDavid.all
  end

  def test_default_scope_with_lambda
    assert_equal [developers(:david).becomes(LazyLambdaDeveloperCalledDavid)], LazyLambdaDeveloperCalledDavid.all
  end

  def test_default_scope_with_block
    assert_equal [developers(:david).becomes(LazyBlockDeveloperCalledDavid)], LazyBlockDeveloperCalledDavid.all
  end

  def test_default_scope_with_callable
    assert_equal [developers(:david).becomes(CallableDeveloperCalledDavid)], CallableDeveloperCalledDavid.all
  end

  def test_default_scope_is_unscoped_on_find
    assert_equal 1, DeveloperCalledDavid.count
    assert_equal 11, DeveloperCalledDavid.unscoped.count
  end

  def test_default_scope_is_unscoped_on_create
    assert_nil DeveloperCalledJamis.unscoped.create!.name
  end

  def test_default_scope_with_conditions_string
    assert_equal Developer.where(name: 'David').map(&:id).sort, DeveloperCalledDavid.all.map(&:id).sort
    assert_equal nil, DeveloperCalledDavid.create!.name
  end

  def test_default_scope_with_conditions_hash
    assert_equal Developer.where(name: 'Jamis').map(&:id).sort, DeveloperCalledJamis.all.map(&:id).sort
    assert_equal 'Jamis', DeveloperCalledJamis.create!.name
  end

  def test_default_scoping_with_threads
    2.times do
      Thread.new { assert DeveloperOrderedBySalary.all.to_sql.include?('salary DESC') }.join
    end
  end

  def test_default_scope_with_inheritance
    wheres = InheritedPoorDeveloperCalledJamis.all.where_values_hash
    assert_equal "Jamis", wheres['name']
    assert_equal 50000,   wheres['salary']
  end

  def test_default_scope_with_module_includes
    wheres = ModuleIncludedPoorDeveloperCalledJamis.all.where_values_hash
    assert_equal "Jamis", wheres['name']
    assert_equal 50000,   wheres['salary']
  end

  def test_default_scope_with_multiple_calls
    wheres = MultiplePoorDeveloperCalledJamis.all.where_values_hash
    assert_equal "Jamis", wheres['name']
    assert_equal 50000,   wheres['salary']
  end

  def test_scope_overwrites_default
    expected = Developer.all.merge!(:order => ' name DESC, salary DESC').to_a.collect { |dev| dev.name }
    received = DeveloperOrderedBySalary.by_name.to_a.collect { |dev| dev.name }
    assert_equal expected, received
  end

  def test_reorder_overrides_default_scope_order
    expected = Developer.order('name DESC').collect { |dev| dev.name }
    received = DeveloperOrderedBySalary.reorder('name DESC').collect { |dev| dev.name }
    assert_equal expected, received
  end

  def test_order_after_reorder_combines_orders
    expected = Developer.order('id DESC, name DESC').collect { |dev| [dev.name, dev.id] }
    received = Developer.order('name ASC').reorder('name DESC').order('id DESC').collect { |dev| [dev.name, dev.id] }
    assert_equal expected, received
  end

  def test_unscope_overrides_default_scope
    expected = Developer.all.collect { |dev| [dev.name, dev.id] }
    received = Developer.order('name ASC, id DESC').unscope(:order).collect { |dev| [dev.name, dev.id] }
    assert_equal expected, received
  end

  def test_unscope_after_reordering_and_combining
    expected = Developer.order('id DESC, name DESC').collect { |dev| [dev.name, dev.id] }
    received = DeveloperOrderedBySalary.reorder('name DESC').unscope(:order).order('id DESC, name DESC').collect { |dev| [dev.name, dev.id] }
    assert_equal expected, received

    expected_2 = Developer.all.collect { |dev| [dev.name, dev.id] }
    received_2 = Developer.order('id DESC, name DESC').unscope(:order).collect { |dev| [dev.name, dev.id] }
    assert_equal expected_2, received_2

    expected_3 = Developer.all.collect { |dev| [dev.name, dev.id] }
    received_3 = Developer.reorder('name DESC').unscope(:order).collect { |dev| [dev.name, dev.id] }
    assert_equal expected_3, received_3
  end

  def test_unscope_with_where_attributes
    expected = Developer.order('salary DESC').collect { |dev| dev.name }
    received = DeveloperOrderedBySalary.where(name: 'David').unscope(where: :name).collect { |dev| dev.name }
    assert_equal expected, received

    expected_2 = Developer.order('salary DESC').collect { |dev| dev.name }
    received_2 = DeveloperOrderedBySalary.select("id").where("name" => "Jamis").unscope({:where => :name}, :select).collect { |dev| dev.name }
    assert_equal expected_2, received_2

    expected_3 = Developer.order('salary DESC').collect { |dev| dev.name }
    received_3 = DeveloperOrderedBySalary.select("id").where("name" => "Jamis").unscope(:select, :where).collect { |dev| dev.name }
    assert_equal expected_3, received_3
  end

  def test_unscope_multiple_where_clauses
    expected = Developer.order('salary DESC').collect { |dev| dev.name }
    received = DeveloperOrderedBySalary.where(name: 'Jamis').where(id: 1).unscope(where: [:name, :id]).collect { |dev| dev.name }
    assert_equal expected, received
  end

  def test_unscope_with_grouping_attributes
    expected = Developer.order('salary DESC').collect { |dev| dev.name }
    received = DeveloperOrderedBySalary.group(:name).unscope(:group).collect { |dev| dev.name }
    assert_equal expected, received

    expected_2 = Developer.order('salary DESC').collect { |dev| dev.name }
    received_2 = DeveloperOrderedBySalary.group("name").unscope(:group).collect { |dev| dev.name }
    assert_equal expected_2, received_2
  end

  def test_unscope_with_limit_in_query
    expected = Developer.order('salary DESC').collect { |dev| dev.name }
    received = DeveloperOrderedBySalary.limit(1).unscope(:limit).collect { |dev| dev.name }
    assert_equal expected, received
  end

  def test_order_to_unscope_reordering
    expected = DeveloperOrderedBySalary.all.collect { |dev| [dev.name, dev.id] }
    received = DeveloperOrderedBySalary.order('salary DESC, name ASC').reverse_order.unscope(:order).collect { |dev| [dev.name, dev.id] }
    assert_equal expected, received
  end

  def test_unscope_reverse_order
    expected = Developer.all.collect { |dev| dev.name }
    received = Developer.order('salary DESC').reverse_order.unscope(:order).collect { |dev| dev.name }
    assert_equal expected, received
  end

  def test_unscope_select
    expected = Developer.order('salary ASC').collect { |dev| dev.name }
    received = Developer.order('salary DESC').reverse_order.select(:name => "Jamis").unscope(:select).collect { |dev| dev.name }
    assert_equal expected, received

    expected_2 = Developer.all.collect { |dev| dev.id }
    received_2 = Developer.select(:name).unscope(:select).collect { |dev| dev.id }
    assert_equal expected_2, received_2
  end

  def test_unscope_offset
    expected = Developer.all.collect { |dev| dev.name }
    received = Developer.offset(5).unscope(:offset).collect { |dev| dev.name }
    assert_equal expected, received
  end

  def test_unscope_joins_and_select_on_developers_projects
    expected = Developer.all.collect { |dev| dev.name }
    received = Developer.joins('JOIN developers_projects ON id = developer_id').select(:id).unscope(:joins, :select).collect { |dev| dev.name }
    assert_equal expected, received
  end

  def test_unscope_includes
    expected = Developer.all.collect { |dev| dev.name }
    received = Developer.includes(:projects).select(:id).unscope(:includes, :select).collect { |dev| dev.name }
    assert_equal expected, received
  end

  def test_unscope_having
    expected = DeveloperOrderedBySalary.all.collect { |dev| dev.name }
    received = DeveloperOrderedBySalary.having("name IN ('Jamis', 'David')").unscope(:having).collect { |dev| dev.name }
    assert_equal expected, received
  end

  def test_unscope_errors_with_invalid_value
    assert_raises(ArgumentError) do
      Developer.includes(:projects).where(name: "Jamis").unscope(:stupidly_incorrect_value)
    end

    assert_raises(ArgumentError) do
      Developer.all.unscope(:includes, :select, :some_broken_value)
    end

    assert_raises(ArgumentError) do
      Developer.order('name DESC').reverse_order.unscope(:reverse_order)
    end

    assert_raises(ArgumentError) do
      Developer.order('name DESC').where(name: "Jamis").unscope()
    end
  end

  def test_unscope_errors_with_non_where_hash_keys
    assert_raises(ArgumentError) do
      Developer.where(name: "Jamis").limit(4).unscope(limit: 4)
    end

    assert_raises(ArgumentError) do
      Developer.where(name: "Jamis").unscope("where" => :name)
    end
  end

  def test_unscope_errors_with_non_symbol_or_hash_arguments
    assert_raises(ArgumentError) do
      Developer.where(name: "Jamis").limit(3).unscope("limit")
    end

    assert_raises(ArgumentError) do
      Developer.select("id").unscope("select")
    end

    assert_raises(ArgumentError) do
      Developer.select("id").unscope(5)
    end
  end

  def test_order_in_default_scope_should_not_prevail
    expected = Developer.all.merge!(:order => 'salary').to_a.collect { |dev| dev.salary }
    received = DeveloperOrderedBySalary.all.merge!(:order => 'salary').to_a.collect { |dev| dev.salary }
    assert_equal expected, received
  end

  def test_create_attribute_overwrites_default_scoping
    assert_equal 'David', PoorDeveloperCalledJamis.create!(:name => 'David').name
    assert_equal 200000, PoorDeveloperCalledJamis.create!(:name => 'David', :salary => 200000).salary
  end

  def test_create_attribute_overwrites_default_values
    assert_equal nil, PoorDeveloperCalledJamis.create!(:salary => nil).salary
    assert_equal 50000, PoorDeveloperCalledJamis.create!(:name => 'David').salary
  end

  def test_default_scope_attribute
    jamis = PoorDeveloperCalledJamis.new(:name => 'David')
    assert_equal 50000, jamis.salary
  end

  def test_where_attribute
    aaron = PoorDeveloperCalledJamis.where(:salary => 20).new(:name => 'Aaron')
    assert_equal 20, aaron.salary
    assert_equal 'Aaron', aaron.name
  end

  def test_where_attribute_merge
    aaron = PoorDeveloperCalledJamis.where(:name => 'foo').new(:name => 'Aaron')
    assert_equal 'Aaron', aaron.name
  end

  def test_scope_composed_by_limit_and_then_offset_is_equal_to_scope_composed_by_offset_and_then_limit
    posts_limit_offset = Post.limit(3).offset(2)
    posts_offset_limit = Post.offset(2).limit(3)
    assert_equal posts_limit_offset, posts_offset_limit
  end

  def test_create_with_merge
    aaron = PoorDeveloperCalledJamis.create_with(:name => 'foo', :salary => 20).merge(
              PoorDeveloperCalledJamis.create_with(:name => 'Aaron')).new
    assert_equal 20, aaron.salary
    assert_equal 'Aaron', aaron.name

    aaron = PoorDeveloperCalledJamis.create_with(:name => 'foo', :salary => 20).
                                     create_with(:name => 'Aaron').new
    assert_equal 20, aaron.salary
    assert_equal 'Aaron', aaron.name
  end

  def test_create_with_reset
    jamis = PoorDeveloperCalledJamis.create_with(:name => 'Aaron').create_with(nil).new
    assert_equal 'Jamis', jamis.name
  end

  # FIXME: I don't know if this is *desired* behavior, but it is *today's*
  # behavior.
  def test_create_with_empty_hash_will_not_reset
    jamis = PoorDeveloperCalledJamis.create_with(:name => 'Aaron').create_with({}).new
    assert_equal 'Aaron', jamis.name
  end

  def test_unscoped_with_named_scope_should_not_have_default_scope
    assert_equal [DeveloperCalledJamis.find(developers(:poor_jamis).id)], DeveloperCalledJamis.poor

    assert DeveloperCalledJamis.unscoped.poor.include?(developers(:david).becomes(DeveloperCalledJamis))
    assert_equal 10, DeveloperCalledJamis.unscoped.poor.length
  end

  def test_default_scope_select_ignored_by_aggregations
    assert_equal DeveloperWithSelect.all.to_a.count, DeveloperWithSelect.count
  end

  def test_default_scope_select_ignored_by_grouped_aggregations
    assert_equal Hash[Developer.all.group_by(&:salary).map { |s, d| [s, d.count] }],
                 DeveloperWithSelect.group(:salary).count
  end

  def test_default_scope_order_ignored_by_aggregations
    assert_equal DeveloperOrderedBySalary.all.count, DeveloperOrderedBySalary.count
  end

  def test_default_scope_find_last
    assert DeveloperOrderedBySalary.count > 1, "need more than one row for test"

    lowest_salary_dev = DeveloperOrderedBySalary.find(developers(:poor_jamis).id)
    assert_equal lowest_salary_dev, DeveloperOrderedBySalary.last
  end

  def test_default_scope_include_with_count
    d = DeveloperWithIncludes.create!
    d.audit_logs.create! :message => 'foo'

    assert_equal 1, DeveloperWithIncludes.where(:audit_logs => { :message => 'foo' }).count
  end

  def test_default_scope_is_threadsafe
    if in_memory_db?
      skip "in memory db can't share a db between threads"
    end

    threads = []
    assert_not_equal 1, ThreadsafeDeveloper.unscoped.count

    threads << Thread.new do
      Thread.current[:long_default_scope] = true
      assert_equal 1, ThreadsafeDeveloper.all.to_a.count
    end
    threads << Thread.new do
      assert_equal 1, ThreadsafeDeveloper.all.to_a.count
    end
    threads.each(&:join)
  end
end
