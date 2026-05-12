require 'spec_helper'
require 'tempfile'

RSpec.describe RailsCodeHealth::RailsAnalyzer do
  let(:temp_file) { Tempfile.new(['test', '.rb']) }
  let(:file_path) { Pathname.new(temp_file.path) }

  after { temp_file.close }

  describe 'controller analysis' do
    context 'with business logic detection' do
      it 'does not flag compound authorization conditionals as business logic' do
        # Under the stricter AST-scoped rules, a plain `if x && y` authorization
        # check is NOT business logic. Only business-verb calls, transactions, or
        # loops-with-conditionals are flagged.
        temp_file.write(<<~RUBY)
          class UsersController < ApplicationController
            def show
              if user.active? && user.premium? && user.verified?
                render :premium_view
              end
            end
          end
        RUBY
        temp_file.rewind

        analyzer = described_class.new(file_path, :controller)
        result = analyzer.analyze

        expect(result[:has_business_logic]).to be false
      end

      it 'detects iteration patterns' do
        temp_file.write(<<~RUBY)
          class UsersController < ApplicationController
            def index
              @users = User.all
              @users.each do |user|
                user.calculate_score
              end
            end
          end
        RUBY
        temp_file.rewind

        analyzer = described_class.new(file_path, :controller)
        result = analyzer.analyze

        expect(result[:has_business_logic]).to be true
      end

      it 'detects business operations' do
        temp_file.write(<<~RUBY)
          class OrdersController < ApplicationController
            def create
              @order = Order.new(params)
              @order.calculate_total
              @order.process_payment
            end
          end
        RUBY
        temp_file.rewind

        analyzer = described_class.new(file_path, :controller)
        result = analyzer.analyze

        expect(result[:has_business_logic]).to be true
      end

      it 'does not flag plain aggregation queries as business logic' do
        # Under the stricter AST-scoped rules, AR aggregation calls (sum, count,
        # average) are not business logic signals. Only business-verb calls,
        # transactions, or loops-with-conditionals are flagged.
        temp_file.write(<<~RUBY)
          class ReportsController < ApplicationController
            def dashboard
              @total_sales = Order.sum(:amount)
              @user_count = User.count
              @average_rating = Review.average(:rating)
            end
          end
        RUBY
        temp_file.rewind

        analyzer = described_class.new(file_path, :controller)
        result = analyzer.analyze

        expect(result[:has_business_logic]).to be false
      end

      it 'detects database transactions' do
        temp_file.write(<<~RUBY)
          class UsersController < ApplicationController
            def create
              User.transaction do
                @user = User.create!(params)
                Profile.create!(user: @user)
              end
            end
          end
        RUBY
        temp_file.rewind

        analyzer = described_class.new(file_path, :controller)
        result = analyzer.analyze

        expect(result[:has_business_logic]).to be true
      end

      it 'does not flag simple controllers' do
        temp_file.write(<<~RUBY)
          class UsersController < ApplicationController
            def show
              @user = User.find(params[:id])
            end

            def create
              @user = User.new(user_params)
              if @user.save
                redirect_to @user
              else
                render :new
              end
            end

            private

            def user_params
              params.require(:user).permit(:name, :email)
            end
          end
        RUBY
        temp_file.rewind

        analyzer = described_class.new(file_path, :controller)
        result = analyzer.analyze

        expect(result[:has_business_logic]).to be false
      end
    end
  end

  describe 'has_direct_model_access? (A1)' do
    it 'flags model access inside a public action' do
      path = RailsCodeHealthFixtures.path_for('controllers/controller_with_direct_model_in_action.rb')
      result = described_class.new(path, :controller).analyze
      expect(result[:has_direct_model_access]).to be true
    end

    it 'does NOT flag model access only inside a private helper' do
      path = RailsCodeHealthFixtures.path_for('controllers/controller_with_model_in_private_helper.rb')
      result = described_class.new(path, :controller).analyze
      expect(result[:has_direct_model_access]).to be false
    end
  end

  describe 'controller action counting (A3)' do
    it 'counts all seven canonical RESTful actions in a thin controller' do
      path = RailsCodeHealthFixtures.path_for('controllers/thin_restful_controller.rb')
      result = described_class.new(path, :controller).analyze
      expect(result[:action_count]).to eq(7)
    end

    it 'excludes private methods from the action count' do
      path = RailsCodeHealthFixtures.path_for('controllers/controller_with_private_helpers.rb')
      result = described_class.new(path, :controller).analyze
      # public: index, show, download = 3
      # private: load_report, report_params (should NOT count)
      expect(result[:action_count]).to eq(3)
    end
  end

  describe 'service analysis' do
    it 'detects instance call method' do
      temp_file.write(<<~RUBY)
        class UserService
          def call
            # service logic
          end
        end
      RUBY
      temp_file.rewind

      analyzer = described_class.new(file_path, :service)
      result = analyzer.analyze

      expect(result[:has_call_method]).to be true
    end

    it 'detects class call method' do
      temp_file.write(<<~RUBY)
        class UserService
          def self.call
            # service logic
          end
        end
      RUBY
      temp_file.rewind

      analyzer = described_class.new(file_path, :service)
      result = analyzer.analyze

      expect(result[:has_call_method]).to be true
    end

    it 'detects missing call method' do
      temp_file.write(<<~RUBY)
        class UserService
          def process
            # service logic
          end
        end
      RUBY
      temp_file.rewind

      analyzer = described_class.new(file_path, :service)
      result = analyzer.analyze

      expect(result[:has_call_method]).to be false
      expect(result[:rails_smells]).to include(
        hash_including(type: :missing_call_method, severity: :high)
      )
    end

    it 'detects dependencies' do
      temp_file.write(<<~RUBY)
        class UserService
          def call
            User.create(name: "test")
            HTTParty.get("http://api.example.com")
            File.read("config.txt")
            UserMailer.welcome.deliver
            Rails.cache.fetch("key")
          end
        end
      RUBY
      temp_file.rewind

      analyzer = described_class.new(file_path, :service)
      result = analyzer.analyze

      expect(result[:dependencies]).to include(:active_record, :external_api, :file_system, :email, :cache)
    end

    it 'detects error handling' do
      temp_file.write(<<~RUBY)
        class UserService
          def call
            begin
              risky_operation
            rescue StandardError => e
              raise CustomError, "Failed"
            end
          end
        end
      RUBY
      temp_file.rewind

      analyzer = described_class.new(file_path, :service)
      result = analyzer.analyze

      expect(result[:error_handling][:rescue_blocks]).to eq(1)
      expect(result[:error_handling][:raise_statements]).to eq(1)
      expect(result[:error_handling][:has_error_handling]).to be true
    end

    it 'calculates complexity score' do
      temp_file.write(<<~RUBY)
        class UserService
          def call
            User.create(name: "test")
            HTTParty.get("http://api.example.com")
            
            if condition1
              # logic
            end
            
            unless condition2
              # logic
            end
            
            case status
            when :active
              # logic
            end
            
            begin
              risky_operation
            rescue StandardError
              raise "Error"
            end
          end
        end
      RUBY
      temp_file.rewind

      analyzer = described_class.new(file_path, :service)
      result = analyzer.analyze

      # Should have complexity from dependencies (2*2=4) + conditionals (1+1+1=3) + error handling (1*2+1=3) = 10
      expect(result[:complexity_score]).to eq(10)
    end

    it 'detects fat service smell' do
      temp_file.write(<<~RUBY)
        class UserService
          def call
            # High complexity service with many dependencies and conditionals
            User.create(name: "test")
            HTTParty.get("http://api.example.com")
            File.read("config.txt")
            UserMailer.welcome.deliver
            Rails.cache.fetch("key")
            
            if condition1 && condition2
              # logic
            end
            
            if condition3
              # logic
            end
            
            unless condition4
              # logic
            end
            
            case status
            when :active
              # logic
            end
          end
        end
      RUBY
      temp_file.rewind

      analyzer = described_class.new(file_path, :service)
      result = analyzer.analyze

      expect(result[:rails_smells]).to include(
        hash_including(type: :fat_service, severity: :high)
      )
    end
  end

  describe 'interactor analysis' do
    it 'detects call method' do
      temp_file.write(<<~RUBY)
        class CreateUser
          def call
            context.user = User.create(context.params)
          end
        end
      RUBY
      temp_file.rewind

      analyzer = described_class.new(file_path, :interactor)
      result = analyzer.analyze

      expect(result[:has_call_method]).to be true
    end

    it 'detects context usage' do
      temp_file.write(<<~RUBY)
        class CreateUser
          def call
            context.user = User.create
            @context.result = "success"
          end
        end
      RUBY
      temp_file.rewind

      analyzer = described_class.new(file_path, :interactor)
      result = analyzer.analyze

      expect(result[:context_usage][:context_references]).to eq(1)
      expect(result[:context_usage][:instance_context_references]).to eq(1)
    end

    it 'detects fail usage' do
      temp_file.write(<<~RUBY)
        class CreateUser
          def call
            context.fail!(error: "Invalid") if invalid?
            fail! if error
          end
        end
      RUBY
      temp_file.rewind

      analyzer = described_class.new(file_path, :interactor)
      result = analyzer.analyze

      expect(result[:fail_usage][:context_fail]).to eq(1)
      expect(result[:fail_usage][:fail_bang]).to eq(1)
    end

    it 'detects organizer pattern' do
      temp_file.write(<<~RUBY)
        class CreateUserOrganizer
          include Interactor::Organizer
          
          organize CreateUser, SendWelcomeEmail
        end
      RUBY
      temp_file.rewind

      analyzer = described_class.new(file_path, :interactor)
      result = analyzer.analyze

      expect(result[:is_organizer]).to be true
    end

    it 'calculates complexity for organizers' do
      temp_file.write(<<~RUBY)
        class ComplexOrganizer
          include Interactor::Organizer
          
          organize CreateUser, SendEmail
          
          def call
            context.user = User.create
            if context.user.valid?
              context.fail!(error: "Invalid")
            end
            
            unless context.success?
              fail!
            end
          end
        end
      RUBY
      temp_file.rewind

      analyzer = described_class.new(file_path, :interactor)
      result = analyzer.analyze

      # Organizer base (5) + context refs (1) + conditionals (1+1=2) + fail usage (1*2+1*2=4) = 12
      expect(result[:complexity_score]).to eq(12)
    end

    it 'detects missing failure handling' do
      temp_file.write(<<~RUBY)
        class CreateUser
          def call
            context.user = User.create
          end
        end
      RUBY
      temp_file.rewind

      analyzer = described_class.new(file_path, :interactor)
      result = analyzer.analyze

      expect(result[:rails_smells]).to include(
        hash_including(type: :missing_failure_handling, severity: :medium)
      )
    end
  end

  describe 'serializer analysis' do
    it 'counts attributes' do
      temp_file.write(<<~RUBY)
        class UserSerializer
          attributes :id, :name, :email
          attribute :full_name
        end
      RUBY
      temp_file.rewind

      analyzer = described_class.new(file_path, :serializer)
      result = analyzer.analyze

      expect(result[:attribute_count]).to eq(2)
    end

    it 'counts associations' do
      temp_file.write(<<~RUBY)
        class UserSerializer
          has_one :profile
          has_many :posts
          belongs_to :company
        end
      RUBY
      temp_file.rewind

      analyzer = described_class.new(file_path, :serializer)
      result = analyzer.analyze

      expect(result[:association_count]).to eq(3)
    end

    it 'counts custom methods' do
      temp_file.write(<<~RUBY)
        class UserSerializer
          def full_name
            "\#{object.first_name} \#{object.last_name}"
          end

          def avatar_url
            object.avatar.url
          end

          def _private_method
            # should be excluded
          end

          def initialize
            # standard method, should be excluded
          end
        end
      RUBY
      temp_file.rewind

      analyzer = described_class.new(file_path, :serializer)
      result = analyzer.analyze

      expect(result[:custom_method_count]).to eq(2)
    end

    it 'detects conditional attributes' do
      temp_file.write(<<~RUBY)
        class UserSerializer
          attributes :id, :name
          attribute :email, if: :show_email?
          attribute :admin, unless: :public_view?
        end
      RUBY
      temp_file.rewind

      analyzer = described_class.new(file_path, :serializer)
      result = analyzer.analyze

      expect(result[:has_conditional_attributes]).to be true
    end

    it 'detects fat serializer smell' do
      temp_file.write(<<~RUBY)
        class UserSerializer
          attributes :id, :name, :email, :first_name, :last_name, :phone
          attributes :address, :city, :state, :zip, :country
          attributes :created_at, :updated_at, :last_login, :status, :role
          
          has_one :profile, :company, :subscription
          has_many :posts, :comments, :orders, :reviews, :notifications
        end
      RUBY
      temp_file.rewind

      analyzer = described_class.new(file_path, :serializer)
      result = analyzer.analyze

      expect(result[:rails_smells]).to include(
        hash_including(type: :fat_serializer, severity: :high)
      )
    end

    it 'detects complex serializer smell' do
      temp_file.write(<<~RUBY)
        class UserSerializer
          def method1; end
          def method2; end
          def method3; end
          def method4; end
          def method5; end
          def method6; end
          def method7; end
          def method8; end
          def method9; end
          def method10; end
          def method11; end
        end
      RUBY
      temp_file.rewind

      analyzer = described_class.new(file_path, :serializer)
      result = analyzer.analyze

      expect(result[:rails_smells]).to include(
        hash_including(type: :complex_serializer, severity: :medium)
      )
    end

    it 'detects empty serializer smell' do
      temp_file.write(<<~RUBY)
        class UserSerializer
        end
      RUBY
      temp_file.rewind

      analyzer = described_class.new(file_path, :serializer)
      result = analyzer.analyze

      expect(result[:rails_smells]).to include(
        hash_including(type: :empty_serializer, severity: :low)
      )
    end
  end

  describe 'has_business_logic? (A2)' do
    it 'flags business-verb calls on model receivers' do
      path = RailsCodeHealthFixtures.path_for('controllers/controller_with_business_logic.rb')
      result = described_class.new(path, :controller).analyze
      expect(result[:has_business_logic]).to be true
    end

    it 'does NOT flag a controller that only does compound authorization checks' do
      # This used to trigger because the old regex matched `if x && y`.
      source = <<~RUBY
        class PostsController < ApplicationController
          def show
            if logged_in? && current_user.admin?
              @post = Post.find(params[:id])
            else
              redirect_to root_path
            end
          end
        end
      RUBY
      file = Tempfile.new(['ctrl', '.rb']).tap { |f| f.write(source); f.rewind }
      result = described_class.new(Pathname.new(file.path), :controller).analyze
      expect(result[:has_business_logic]).to be false
    ensure
      file&.close
    end

    it 'does NOT flag plain iteration without a conditional inside' do
      source = <<~RUBY
        class UsersController < ApplicationController
          def index
            @users = User.all
            @users.each { |u| u.touch }
          end
        end
      RUBY
      file = Tempfile.new(['ctrl', '.rb']).tap { |f| f.write(source); f.rewind }
      result = described_class.new(Pathname.new(file.path), :controller).analyze
      expect(result[:has_business_logic]).to be false
    ensure
      file&.close
    end

    it 'does NOT flag controllers that only read AR attributes with process_ in the name' do
      # Regression: `process_id` is a common attribute. Earlier impls flagged this.
      source = <<~RUBY
        class JobsController < ApplicationController
          def show
            @job_id = current_job.process_id
            render json: { job_id: @job_id }
          end
        end
      RUBY
      file = Tempfile.new(['ctrl', '.rb']).tap { |f| f.write(source); f.rewind }
      result = described_class.new(Pathname.new(file.path), :controller).analyze
      expect(result[:has_business_logic]).to be false
    ensure
      file&.close
    end
  end

  describe 'model macro counts (A4)' do
    it 'does not count commented-out macros' do
      path = RailsCodeHealthFixtures.path_for('models/model_with_validations_in_comments.rb')
      result = described_class.new(path, :model).analyze
      expect(result[:validation_count]).to eq(1)
      expect(result[:association_count]).to eq(2) # belongs_to :user, has_many :comments
    end

    it 'counts macros only at the class body level' do
      # `included do ... end` blocks live inside the class body but their contents
      # are inside a block, so we don't descend into them.
      path = RailsCodeHealthFixtures.path_for('models/model_with_concerns_block.rb')
      result = described_class.new(path, :model).analyze
      # Top-level: has_many :tags (1 association), validates :title (1 validation).
      # The `included do` content is NOT counted.
      expect(result[:association_count]).to eq(1)
      expect(result[:validation_count]).to eq(1)
    end
  end

  describe 'has_fat_model_smell? (A5)' do
    it 'does not flag a thin model' do
      path = RailsCodeHealthFixtures.path_for('models/thin_model.rb')
      result = described_class.new(path, :model).analyze
      expect(result[:has_fat_model_smell]).to be false
    end

    it 'flags a model that exceeds thresholds in class-scoped lines AND methods' do
      path = RailsCodeHealthFixtures.path_for('models/fat_model.rb')
      result = described_class.new(path, :model).analyze
      expect(result[:has_fat_model_smell]).to be true
    end
  end

  describe 'view logic counting (A7)' do
    it 'counts ERB tags containing control flow as logic lines' do
      path = RailsCodeHealthFixtures.path_for('views/view_with_logic.html.erb')
      result = described_class.new(path, :view).analyze
      # 4 tags contain control flow: if, else, end (twice in pairs), each ... + 2 ends
      # Acceptable to assert "> 0 and >= 4" rather than exact, since semantics
      # of "end" tags are debatable.
      expect(result[:logic_lines]).to be >= 4
    end

    it 'does NOT count plain HTML lines with keywords in prose' do
      path = RailsCodeHealthFixtures.path_for('views/view_with_keyword_in_text.html.erb')
      result = described_class.new(path, :view).analyze
      expect(result[:logic_lines]).to eq(0)
    end

    it 'returns zero logic for a plain view with only output ERB' do
      path = RailsCodeHealthFixtures.path_for('views/simple_view.html.erb')
      result = described_class.new(path, :view).analyze
      # `<%= @user.name %>` is output-only, no control flow.
      expect(result[:logic_lines]).to eq(0)
    end
  end

  describe 'migration data changes (A6)' do
    it 'does not flag a schema-only migration' do
      path = RailsCodeHealthFixtures.path_for('migrations/schema_only_migration.rb')
      result = described_class.new(path, :migration).analyze
      expect(result[:has_data_changes]).to be false
    end

    it 'flags a migration that uses find_each + update_columns' do
      path = RailsCodeHealthFixtures.path_for('migrations/migration_with_find_each.rb')
      result = described_class.new(path, :migration).analyze
      expect(result[:has_data_changes]).to be true
    end

    it 'flags a migration that runs raw SQL via connection.execute' do
      path = RailsCodeHealthFixtures.path_for('migrations/migration_with_raw_sql.rb')
      result = described_class.new(path, :migration).analyze
      expect(result[:has_data_changes]).to be true
    end
  end

  describe 'service dependency detection (A8)' do
    it 'returns no dependencies for a trivial service' do
      path = RailsCodeHealthFixtures.path_for('services/plain_service.rb')
      result = described_class.new(path, :service).analyze
      expect(result[:dependencies]).to eq([])
    end

    it 'does NOT mistake Profile. for File.' do
      path = RailsCodeHealthFixtures.path_for('services/service_with_profile_model.rb')
      result = described_class.new(path, :service).analyze
      expect(result[:dependencies]).to include(:active_record)
      expect(result[:dependencies]).not_to include(:file_system)
    end
  end
end
