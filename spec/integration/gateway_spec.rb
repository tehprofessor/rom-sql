require 'spec_helper'

describe ROM::SQL::Gateway do
  describe 'migration' do
    let(:conn) { Sequel.connect(POSTGRES_DB_URI) }

    context 'creating migrations inline' do
      subject(:gateway) { container.gateways[:default] }

      let(:configuration) { ROM::Configuration.new(:sql, conn) }
      let!(:container) { ROM.container(configuration) }

      after do
        [:rabbits, :carrots].each do |name|
          gateway.connection.drop_table?(name)
        end
      end

      it 'allows creating and running migrations' do
        migration = gateway.migration do
          up do
            create_table(:rabbits) do
              primary_key :id
              String :name
            end
          end

          down do
            drop_table(:rabbits)
          end
        end

        migration.apply(gateway.connection, :up)

        expect(gateway.connection[:rabbits]).to be_a(Sequel::Dataset)

        migration.apply(gateway.connection, :down)

        expect(gateway.connection.tables).to_not include(:rabbits)
      end
    end

    context 'running migrations from a file system' do
      include_context 'database setup'

      let(:migration_dir) do
        Pathname(__FILE__).dirname.join('../fixtures/migrations').realpath
      end

      let(:migrator) { ROM::SQL::Migration::Migrator.new(conn, path: migration_dir) }
      let(:configuration) { ROM::Configuration.new(:sql, [conn, migrator: migrator]) }
      let!(:container) { ROM.container(configuration) }

      it 'returns true for pending migrations' do
        expect(container.gateways[:default].pending_migrations?).to be_truthy
      end

      it 'returns false for non pending migrations' do
        container.gateways[:default].run_migrations
        expect(container.gateways[:default].pending_migrations?).to be_falsy
      end

      it 'runs migrations from a specified directory' do
        container.gateways[:default].run_migrations
      end
    end
  end

  context 'setting up' do
    include_context 'database setup'

    it 'skips settings up associations when tables are missing' do
      configuration = ROM::Configuration.new(:sql, uri) do |config|
        config.relation(:foos) do
          use :assoc_macros
          one_to_many :bars, key: :foo_id
        end
      end
      expect { ROM.container(configuration) }.not_to raise_error
    end

    it 'skips finalization a relation when table is missing' do
      configuration = ROM::Configuration.new(:sql, uri) do |config|
        class Foos < ROM::Relation[:sql]
          dataset :foos
          use :assoc_macros
          one_to_many :bars, key: :foo_id
        end
      end

      expect { ROM.container(configuration) }.not_to raise_error
      expect { Foos.model.dataset }.to raise_error(Sequel::Error, /no dataset/i)
    end
  end
end
