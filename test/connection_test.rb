require 'test/test_helper'
require 'logger'
require 'stringio'
require 'thread'

# NOTE: assumes Mongo is running
class TestConnection < Test::Unit::TestCase

  include Mongo

  def setup
    @host = ENV['MONGO_RUBY_DRIVER_HOST'] || 'localhost'
    @port = ENV['MONGO_RUBY_DRIVER_PORT'] || Connection::DEFAULT_PORT
    @mongo = Connection.new(@host, @port)
  end

  def teardown
    @mongo.db('ruby-mongo-test').error
  end

  def test_server_info
    server_info = @mongo.server_info
    assert server_info.keys.include?("version")
    assert_equal 1.0, server_info["ok"]
  end

  def test_server_version
    assert_match /\d\.\d+(\.\d+)?/, @mongo.server_version.to_s
  end

  def test_invalid_database_names
    assert_raise TypeError do @mongo.db(4) end

    assert_raise InvalidName do @mongo.db('') end
    assert_raise InvalidName do @mongo.db('te$t') end
    assert_raise InvalidName do @mongo.db('te.t') end
    assert_raise InvalidName do @mongo.db('te\\t') end
    assert_raise InvalidName do @mongo.db('te/t') end
    assert_raise InvalidName do @mongo.db('te st') end
  end

  def test_database_info
    @mongo.drop_database('ruby-mongo-info-test')
    @mongo.db('ruby-mongo-info-test').collection('info-test').insert('a' => 1)

    info = @mongo.database_info
    assert_not_nil info
    assert_kind_of Hash, info
    assert_not_nil info['ruby-mongo-info-test']
    assert info['ruby-mongo-info-test'] > 0

    @mongo.drop_database('ruby-mongo-info-test')
  end

  def test_copy_database
    @mongo.db('old').collection('copy-test').insert('a' => 1)
    @mongo.copy_database('old', 'new')
    old_object = @mongo.db('old').collection('copy-test').find.next_document
    new_object = @mongo.db('new').collection('copy-test').find.next_document
    assert_equal old_object, new_object
  end

  def test_database_names
    @mongo.drop_database('ruby-mongo-info-test')
    @mongo.db('ruby-mongo-info-test').collection('info-test').insert('a' => 1)

    names = @mongo.database_names
    assert_not_nil names
    assert_kind_of Array, names
    assert names.length >= 1
    assert names.include?('ruby-mongo-info-test')
  end

  def test_logging
    output = StringIO.new
    logger = Logger.new(output)
    logger.level = Logger::DEBUG
    db = Connection.new(@host, @port, :logger => logger).db('ruby-mongo-test')
    assert output.string.include?("admin.$cmd.find")
  end

  def test_connection_logger
    output = StringIO.new
    logger = Logger.new(output)
    logger.level = Logger::DEBUG
    connection = Connection.new(@host, @port, :logger => logger)
    assert_equal logger, connection.logger
    
    connection.logger.debug 'testing'
    assert output.string.include?('testing')
  end

  def test_drop_database
    db = @mongo.db('ruby-mongo-will-be-deleted')
    coll = db.collection('temp')
    coll.remove
    coll.insert(:name => 'temp')
    assert_equal 1, coll.count()
    assert @mongo.database_names.include?('ruby-mongo-will-be-deleted')

    @mongo.drop_database('ruby-mongo-will-be-deleted')
    assert !@mongo.database_names.include?('ruby-mongo-will-be-deleted')
  end

  def test_nodes
    db = Connection.new({:left => ['foo', 123]}, nil, :connect => false)
    nodes = db.nodes
    assert_equal 2, db.nodes.length
    assert_equal ['foo', 123], nodes[0]
    assert_equal ['localhost', Connection::DEFAULT_PORT], nodes[1]

    db = Connection.new({:right => 'bar'}, nil, :connect => false)
    nodes = db.nodes
    assert_equal 2, nodes.length
    assert_equal ['localhost', Connection::DEFAULT_PORT], nodes[0]
    assert_equal ['bar', Connection::DEFAULT_PORT], nodes[1]

    db = Connection.new({:right => ['foo', 123], :left => 'bar'}, nil, :connect => false)
    nodes = db.nodes
    assert_equal 2, nodes.length
    assert_equal ['bar', Connection::DEFAULT_PORT], nodes[0]
    assert_equal ['foo', 123], nodes[1]
  end

  context "Saved authentications" do
    setup do
      @conn = Mongo::Connection.new
      @auth = {'db_name' => 'test', 'username' => 'bob', 'password' => 'secret'}
      @conn.add_auth(@auth['db_name'], @auth['username'], @auth['password'])
    end

    should "save the authentication" do
      assert_equal @auth, @conn.auths[0]
    end

    should "replace the auth if given a new auth for the same db" do
      auth = {'db_name' => 'test', 'username' => 'mickey', 'password' => 'm0u53'}
      @conn.add_auth(auth['db_name'], auth['username'], auth['password'])
      assert_equal 1, @conn.auths.length
      assert_equal auth, @conn.auths[0]
    end

    should "remove auths by database" do
      @conn.remove_auth('non-existent database')
      assert_equal 1, @conn.auths.length

      @conn.remove_auth('test')
      assert_equal 0, @conn.auths.length
    end

    should "remove all auths" do
      @conn.clear_auths
      assert_equal 0, @conn.auths.length
    end
  end

  context "Connection exceptions" do
    setup do
      @conn = Mongo::Connection.new('localhost', 27017, :pool_size => 10, :timeout => 10)
      @coll = @conn['mongo-ruby-test']['test-connection-exceptions']
    end

    should "release connection if an exception is raised on send_message" do
      @conn.stubs(:send_message_on_socket).raises(ConnectionFailure)
      assert_equal 0, @conn.checked_out.size
      assert_raise ConnectionFailure do
        @coll.insert({:test => "insert"})
      end
      assert_equal 0, @conn.checked_out.size
    end

    should "release connection if an exception is raised on send_with_safe_check" do
      @conn.stubs(:receive).raises(ConnectionFailure)
      assert_equal 0, @conn.checked_out.size
      assert_raise ConnectionFailure do
        @coll.insert({:test => "insert"}, :safe => true)
      end
      assert_equal 0, @conn.checked_out.size
    end

    should "release connection if an exception is raised on receive_message" do
      @conn.stubs(:receive).raises(ConnectionFailure)
      assert_equal 0, @conn.checked_out.size
      assert_raise ConnectionFailure do
        @coll.find.to_a
      end
      assert_equal 0, @conn.checked_out.size
    end
  end
end
