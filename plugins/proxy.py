#!/usr/bin/python
# -*- coding: utf-8 -*-
#
# proxy.py — helper for Python-based external (xml-rpc) ikiwiki plugins
#
# Copyright © 2008      martin f. krafft <madduck@madduck.net>
#             2008-2011 Joey Hess <joey@kitenet.net>
#             2012      W. Trevor King <wking@tremily.us>
#
#  Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
# .
# THIS SOFTWARE IS PROVIDED BY IKIWIKI AND CONTRIBUTORS ``AS IS''
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
# TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
# PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE FOUNDATION
# OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
# LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF
# USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT
# OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.
#
__name__ = 'proxy.py'
__description__ = 'helper for Python-based external (xml-rpc) ikiwiki plugins'
__version__ = '0.2'
__author__ = 'martin f. krafft <madduck@madduck.net>'
__copyright__ = 'Copyright © ' + __author__
__licence__ = 'BSD-2-clause'

import sys
import time
import xml.parsers.expat
try:  # Python 3
    import xmlrpc.client as _xmlrpc_client
except ImportError:  # Python 2
    import xmlrpclib as _xmlrpc_client
try:  # Python 3
    import xmlrpc.server as _xmlrpc_server
except ImportError:  # Python 2
    import SimpleXMLRPCServer as _xmlrpc_server


class ParseError (Exception):
    pass


class PipeliningDetected (Exception):
    pass


class GoingDown (Exception):
    pass


class InvalidReturnValue (Exception):
    pass


class AlreadyImported (Exception):
    pass


class _IkiWikiExtPluginXMLRPCDispatcher(_xmlrpc_server.SimpleXMLRPCDispatcher):

    def __init__(self, allow_none=False, encoding=None):
        try:
            _xmlrpc_server.SimpleXMLRPCDispatcher.__init__(
                self, allow_none, encoding)
        except TypeError:
            # see http://bugs.debian.org/470645
            # python2.4 and before only took one argument
            _xmlrpc_server.SimpleXMLRPCDispatcher.__init__(self)

    def dispatch(self, method, params):
        return self._dispatch(method, params)


class XMLStreamParser(object):

    def __init__(self):
        self._parser = xml.parsers.expat.ParserCreate()
        self._parser.StartElementHandler = self._push_tag
        self._parser.EndElementHandler = self._pop_tag
        self._parser.XmlDeclHandler = self._check_pipelining
        self._reset()

    def _reset(self):
        self._stack = list()
        self._acc = r''
        self._first_tag_received = False

    def _push_tag(self, tag, attrs):
        self._stack.append(tag)
        self._first_tag_received = True

    def _pop_tag(self, tag):
        top = self._stack.pop()
        if top != tag:
            raise ParseError(
                'expected {0} closing tag, got {1}'.format(top, tag))

    def _request_complete(self):
        return self._first_tag_received and len(self._stack) == 0

    def _check_pipelining(self, *args):
        if self._first_tag_received:
            raise PipeliningDetected('need a new line between XML documents')

    def parse(self, data):
        self._parser.Parse(data, False)
        self._acc += data
        if self._request_complete():
            ret = self._acc
            self._reset()
            return ret


class _IkiWikiExtPluginXMLRPCHandler(object):

    def __init__(self, debug_fn):
        self._dispatcher = _IkiWikiExtPluginXMLRPCDispatcher()
        self.register_function = self._dispatcher.register_function
        self._debug_fn = debug_fn

    def register_function(self, function, name=None):
        # will be overwritten by __init__
        pass

    @staticmethod
    def _write(out_fd, data):
        out_fd.write(str(data))
        out_fd.flush()

    @staticmethod
    def _read(in_fd):
        ret = None
        parser = XMLStreamParser()
        while True:
            line = in_fd.readline()
            if len(line) == 0:
                # ikiwiki exited, EOF received
                return None

            ret = parser.parse(line)
            # unless this returns non-None, we need to loop again
            if ret is not None:
                return ret

    def send_rpc(self, cmd, in_fd, out_fd, *args, **kwargs):
        xml = _xmlrpc_client.dumps(sum(kwargs.items(), args), cmd)
        self._debug_fn(
            "calling ikiwiki procedure `{0}': [{1}]".format(cmd, repr(xml)))
        # ensure that encoded is a str (bytestring in Python 2, Unicode in 3)
        if str is bytes and not isinstance(xml, str):
            encoded = xml.encode('utf8')
        else:
            encoded = xml
        _IkiWikiExtPluginXMLRPCHandler._write(out_fd, encoded)

        self._debug_fn('reading response from ikiwiki...')

        response = _IkiWikiExtPluginXMLRPCHandler._read(in_fd)
        if str is bytes and not isinstance(response, str):
            xml = response.encode('utf8')
        else:
            xml = response
        self._debug_fn(
            'read response to procedure {0} from ikiwiki: [{1}]'.format(
                cmd, repr(xml)))
        if xml is None:
            # ikiwiki is going down
            self._debug_fn('ikiwiki is going down, and so are we...')
            raise GoingDown()

        data = _xmlrpc_client.loads(xml)[0][0]
        self._debug_fn(
            'parsed data from response to procedure {0}: [{1}]'.format(
                cmd, repr(data)))
        return data

    def handle_rpc(self, in_fd, out_fd):
        self._debug_fn('waiting for procedure calls from ikiwiki...')
        xml = _IkiWikiExtPluginXMLRPCHandler._read(in_fd)
        if xml is None:
            # ikiwiki is going down
            self._debug_fn('ikiwiki is going down, and so are we...')
            raise GoingDown()

        self._debug_fn(
            'received procedure call from ikiwiki: [{0}]'.format(xml))
        params, method = _xmlrpc_client.loads(xml)
        ret = self._dispatcher.dispatch(method, params)
        xml = _xmlrpc_client.dumps((ret,), methodresponse=True)
        self._debug_fn(
                'sending procedure response to ikiwiki: [{0}]'.format(xml))
        _IkiWikiExtPluginXMLRPCHandler._write(out_fd, xml)
        return ret


class IkiWikiProcedureProxy(object):

    # how to communicate None to ikiwiki
    _IKIWIKI_NIL_SENTINEL = {'null':''}

    # sleep during each iteration
    _LOOP_DELAY = 0.1

    def __init__(self, id, in_fd=sys.stdin, out_fd=sys.stdout, debug_fn=None):
        self._id = id
        self._in_fd = in_fd
        self._out_fd = out_fd
        self._hooks = list()
        self._functions = list()
        self._imported = False
        if debug_fn is not None:
            self._debug_fn = debug_fn
        else:
            self._debug_fn = lambda s: None
        self._xmlrpc_handler = _IkiWikiExtPluginXMLRPCHandler(self._debug_fn)
        self._xmlrpc_handler.register_function(self._importme, name='import')

    def rpc(self, cmd, *args, **kwargs):
        def subst_none(seq):
            for i in seq:
                if i is None:
                    yield IkiWikiProcedureProxy._IKIWIKI_NIL_SENTINEL
                else:
                    yield i

        args = list(subst_none(args))
        kwargs = dict(zip(kwargs.keys(), list(subst_none(kwargs.values()))))
        ret = self._xmlrpc_handler.send_rpc(cmd, self._in_fd, self._out_fd,
                                            *args, **kwargs)
        if ret == IkiWikiProcedureProxy._IKIWIKI_NIL_SENTINEL:
            ret = None
        return ret

    def hook(self, type, function, name=None, id=None, last=False):
        if self._imported:
            raise AlreadyImported()

        if name is None:
            name = function.__name__

        if id is None:
            id = self._id

        def hook_proxy(*args):
#            curpage = args[0]
#            kwargs = dict([args[i:i+2] for i in xrange(1, len(args), 2)])
            ret = function(self, *args)
            self._debug_fn(
                    "{0} hook `{1}' returned: [{2}]".format(type, name, repr(ret)))
            if ret == IkiWikiProcedureProxy._IKIWIKI_NIL_SENTINEL:
                raise InvalidReturnValue(
                    'hook functions are not allowed to return {0}'.format(
                        IkiWikiProcedureProxy._IKIWIKI_NIL_SENTINEL))
            if ret is None:
                ret = IkiWikiProcedureProxy._IKIWIKI_NIL_SENTINEL
            return ret

        self._hooks.append((id, type, name, last))
        self._xmlrpc_handler.register_function(hook_proxy, name=name)

    def inject(self, rname, function, name=None, memoize=True):
        if self._imported:
            raise AlreadyImported()

        if name is None:
            name = function.__name__

        self._functions.append((rname, name, memoize))
        self._xmlrpc_handler.register_function(function, name=name)

    def getargv(self):
        return self.rpc('getargv')

    def setargv(self, argv):
        return self.rpc('setargv', argv)

    def getvar(self, hash, key):
        return self.rpc('getvar', hash, key)

    def setvar(self, hash, key, value):
        return self.rpc('setvar', hash, key, value)

    def getstate(self, page, id, key):
        return self.rpc('getstate', page, id, key)

    def setstate(self, page, id, key, value):
        return self.rpc('setstate', page, id, key, value)

    def pagespec_match(self, spec):
        return self.rpc('pagespec_match', spec)

    def error(self, msg):
        try:
            self.rpc('error', msg)
        except IOError as e:
            if e.errno != 32:
                raise
        import posix
        sys.exit(posix.EX_SOFTWARE)

    def run(self):
        try:
            while True:
                ret = self._xmlrpc_handler.handle_rpc(
                    self._in_fd, self._out_fd)
                time.sleep(IkiWikiProcedureProxy._LOOP_DELAY)
        except GoingDown:
            return

        except Exception as e:
            import traceback
            tb = traceback.format_exc()
            self.error('uncaught exception: {0}\n{1}'.format(e, tb))
            return

    def _importme(self):
        self._debug_fn('importing...')
        for id, type, function, last in self._hooks:
            self._debug_fn('hooking {0}/{1} into {2} chain...'.format(
                    id, function, type))
            self.rpc('hook', id=id, type=type, call=function, last=last)
        for rname, function, memoize in self._functions:
            self._debug_fn('injecting {0} as {1}...'.format(function, rname))
            self.rpc('inject', name=rname, call=function, memoize=memoize)
        self._imported = True
        return IkiWikiProcedureProxy._IKIWIKI_NIL_SENTINEL
