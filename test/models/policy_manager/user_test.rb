require 'test_helper'

module PolicyManager
  class UserTest < ActiveSupport::TestCase

    def setup
      @config = PolicyManager::Config.setup do |c|
        c.add_rule({name: "age", validates_on: [:create, :update], if: ->(o){ o.enabled_for_validation } })
        c.from_email = "foo@bar.org"
        c.admin_email_inbox = "foo@baaz.org"
        c.user_language_method = -> (o){ o.lang }
        c.exporter = { 
          path: Rails.root + "tmp/export", 
          resource: User ,
          index_template: '<h1>index template, custom</h1>
                          <ul>
                            <% @collection.each do |rule| %>
                              <li><%= link_to rule.name, "./#{rule.name}/index.html" %></li>
                            <% end %>
                          </ul>',
          layout: "<body>
                  <h1>layout header</h1>
                  <%= yield %>
                  <footer>layout footer</footer>
                  </body>",
          after_zip: ->(zip_path, resource){ 
            puts "THIS IS GREAT #{zip_path} was zipped, now what ??" 
          }
        }
      end

      if defined?(User)
        Object.send(:remove_const, :User)
        load Rails.root + 'app/models/user.rb'
      end

      pr = PolicyManager::Term.create(description: "el", rule: "age")
      pr.publish!
    end

    test "dummy user creation with validation rules" do
      user = User.create(email: "a@a.cl")
      assert user.errors.any?
      assert user.errors[:policy_rule_age].present?
      user = User.create(email: "a@a.cl", policy_rule_age: true)
      assert user.persisted?
    end

    test "dummy user creation without validation rules (if)" do
      User.stub_any_instance(:enabled_for_validation, false) do
        user = User.create(email: "a@a.cl")
        assert !user.errors.any?
      end
    end

    test "get policies on empty terms will not return pending policies" do
      user = User.create(email: "a@a.cl", policy_rule_age: true)
      assert user.pending_policies.size == 0
    end

    test "has_consented_meth?" do
      user = User.create(email: "a@a.cl", policy_rule_age: true)
      assert user.has_consented_age?
    end

    test "create without policy" do
      user = User.create(email: "a@a.cl")
      assert user.errors.any?
    end

    test "get policies on existing terms will return pending policies" do
      pr = PolicyManager::Term.create(description: "aaa", rule: config.rules.first.name)
      pr.publish!
      user = User.create(email: "a@a.cl", policy_rule_age: true)
      pr = PolicyManager::Term.create(description: "version 2", rule: "age")
      pr.publish!
      assert user.pending_policies.size == 1
      assert user.needs_policy_confirmation_for?(config.rules.first.name)
    end

    test "accept policies will empty pending policies" do
      pr = PolicyManager::Term.create(description: "aaa", rule: config.rules.first.name)
      pr.publish!
      user = User.create(email: "a@a.cl", policy_rule_age: true)
      pr = PolicyManager::Term.create(description: "version 2", rule: "age")
      pr.publish!
      assert user.pending_policies.size == 1
      user_term = user.handle_policy_for(config.rules.first.terms.last)
      user_term.accept!
      assert user.pending_policies.size == 0
    end

    test "can request portability" do
      User.stub_any_instance(:enabled_for_validation, false) do
        user = User.create(email: "a@a.cl")
        assert !user.errors.any?
        assert user.can_request_portability?
        preq = user.portability_requests.create
        preq.confirm!
      end
    end

    test "can't request portability if has one pending" do
      User.stub_any_instance(:enabled_for_validation, false) do
        user = User.create(email: "a@a.cl")
        assert !user.errors.any?
        assert user.can_request_portability?
        preq = user.portability_requests.create
        assert !user.can_request_portability?
      end
    end

    test "can't request portability if has one in progress" do
      User.stub_any_instance(:enabled_for_validation, false) do
        user = User.create(email: "a@a.cl")
        assert !user.errors.any?
        assert user.can_request_portability?
        preq = user.portability_requests.create
        preq.confirm!
        assert !user.can_request_portability?
      end
    end

  end
end
