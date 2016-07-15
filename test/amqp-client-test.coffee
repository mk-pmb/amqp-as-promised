{EventEmitter}  = require 'events'
Q               = require 'q'
QueueWrapper    = require '../src/queue-wrapper'
ExchangeWrapper = require '../src/exchange-wrapper'

amqp = amqpc = amqpClient = nodeAmqp = queue = exchange = exEvents = qEvents = undefined
            
describe 'AmqpClient', ->

    beforeEach ->
        amqp = new EventEmitter
        queue = new EventEmitter
        queue.bind = -> @emit 'queueBindOk'
        queue.subscribe = -> { addCallback: (cb) -> cb { } }
        exEvents = new EventEmitter
        exchange = {}
        qEvents = new EventEmitter
        amqp.queue = (name, obts, cb) ->
            cb queue
            queue.emit 'open'
            return qEvents
        amqp.exchange = (name, opts, cb) ->
            cb exchange
            return exEvents
        nodeAmqp = { createConnection: stub().returns amqp }
        amqpClient = proxyquire '../src/amqp-client',
            'amqp': nodeAmqp
        amqpc = amqpClient { connection:url:'url' }
        amqp.emit 'ready'

    describe 'conn', ->
        it 'should invoke amqp.createConnection with the connection parameters', ->
            amqpc.exchange('panda').then ->
                nodeAmqp.createConnection.should.have.been.calledWith { url: 'url' }

    describe 'connection error', ->

        it 'should crash the process', -> amqpc.exchange('panda').then ->
            expect ->
                amqp.emit 'error', new Error("failed badly")
            .to.throw 'failed badly'

        it 'notifies a conf.errorHandler if configured', ->
            handler = spy ->
            amqp = new EventEmitter
            nodeAmqp = { createConnection: stub().returns amqp }
            amqpClient = proxyquire '../src/amqp-client',
                'amqp': nodeAmqp
            amqpc = amqpClient { connection:{url:'url'}, errorHandler:handler }
            amqp.emit 'ready'
            handler.should.not.have.been.calledOnce
            amqp.emit 'error', new Error("failed badly")
            handler.should.have.been.calledOnce

    describe '.queue()', ->
        beforeEach ->
            spy amqp, 'queue'

        it 'should assume exclusive:true when called without name and opts', ->
            amqpc.queue().then ->
                amqp.queue.should.have.been.calledWith '', { exclusive: true }
        it 'should assume passive:true when called with name but without opts', ->
            amqpc.queue('panda').then ->
                amqp.queue.should.have.been.calledWith 'panda', { passive:true }
        it 'should pass given name and opts on when creating the queue', ->
            amqpc.queue('panda', { my: 'option' }).then ->
                amqp.queue.should.have.been.calledWith 'panda', { my: 'option' }
        it 'should returns a promise for a QueueWrapper', ->
            amqpc.queue().should.eventually.be.an.instanceof QueueWrapper
        it 'should pass a reference to itself to QueueWrapper', ->
            amqpc.queue().then (q) ->
                q.amqpc.should.equal amqpc
        it 'should return the same object if passed a QueueWrapper as only argument', ->
            amqpc.queue('panda').then (q1) ->
                amqpc.queue(q1).then (q2) ->
                    expect(q1).to.equal q2
        it 'should catch errors signalled by amqp, and reject the queue promise', ->
            amqp.queue = (name, opts, cb) ->
                return qEvents
            setTimeout (-> qEvents.emit 'error', 'Error!'), 10
            amqpc.queue('panda').should.be.rejectedWith 'Error!'

    describe '.exchange()', ->
        beforeEach ->
            spy amqp, 'exchange'
            
        describe 'should set the confirm flag when creating an exchange', ->
            it 'with explicit options', ->
                amqpc.exchange('panda', { durable: true }).then ->
                    amqp.exchange.should.have.been.calledWith 'panda', { durable: true, confirm: true }
            it 'without explicit options', ->
                amqpc.exchange('panda').then ->
                    amqp.exchange.should.have.been.calledWith 'panda', { passive: true, confirm: true }

        describe 'should not set the confirm flag for the default exchange when creating an exchange', ->
            it 'with explicit options', ->
                amqpc.exchange('', { durable: true }).then ->
                    amqp.exchange.should.have.been.calledWith '', { durable: true }
            it 'without explicit options', ->
                amqpc.exchange('').then ->
                    amqp.exchange.should.have.been.calledWith '', { passive: true }

        it 'should return an ExchangeWrapper', ->
            amqpc.exchange('panda').should.eventually.be.an.instanceof ExchangeWrapper

        it 'should return the same object if passed an ExchangeWrapper as only argument', ->
            amqpc.exchange('panda').then (ex1) ->
                amqpc.exchange(ex1).then (ex2) ->
                    expect(ex1).to.equal ex2

        it 'should catch errors signalled by amqp, and reject the exchange promise', ->
            amqp.exchange = (name, opts, cb) ->
                return exEvents
            setTimeout (-> exEvents.emit 'error', 'Error!'), 10
            amqpc.exchange('panda').should.be.rejectedWith 'Error!'
            
    describe '.bind()', ->
        
        it 'should catch exchange errors signalled by amqp, and reject the bind promise', ->
            amqp.exchange = (name, opts, cb) ->
                return exEvents
            setTimeout (-> exEvents.emit 'error', 'Error!'), 10
            amqpc.bind('panda', 'cub', '#').should.be.rejectedWith 'Error!'
            
        it 'should catch queue errors signalled by amqp, and reject the bind promise', ->
            amqp.queue = (name, opts, cb) ->
                return qEvents
            setTimeout (-> qEvents.emit 'error', 'Error!'), 10
            amqpc.bind('panda', 'cub', '#').should.be.rejectedWith 'Error!'
    
        it 'should use the named (passive) queue when no queue name is supplied', ->
            spy amqp, 'queue'
            spy queue, 'bind'
            amqpc.bind('panda', 'cub', '#').then ->
                amqp.queue.should.have.been.calledWith 'cub', { passive: true }
                queue.bind.should.have.been.calledWith exchange, '#'

        it 'should declare an anonymous queue when no queue name is supplied', ->
            spy amqp, 'queue'
            spy queue, 'bind'
            amqpc.bind('panda', '#', ->).then ->
                amqp.queue.should.have.been.calledWith '', { exclusive: true }
                queue.bind.should.have.been.calledWith exchange, '#'
        
        it 'should subscribe the callback, if present', ->
            cb = spy()
            spy queue, 'subscribe'
            amqpc.bind('panda', 'cub', '#', cb).then ->
                queue.subscribe.should.have.been.calledWith match.object, match.func
                cb.should.not.have.been.called
                queue.subscribe.firstCall.args[1]()
                cb.should.have.been.calledOnce
                
    describe '.unbind()', ->

        it 'should unbind the underlying queue', ->
            amqpc.queue('cub').then (q) ->
                spy q, 'unbind'
                amqpc.unbind('cub').then ->
                    q.unbind.should.have.been.calledOnce

        it 'should unsubscribe the underlying queue', ->
            amqpc.queue('cub').then (q) ->
                spy q, 'unsubscribe'
                amqpc.unbind('cub').then ->
                    q.unsubscribe.should.have.been.calledOnce
