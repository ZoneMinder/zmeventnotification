import logging
import logging.handlers
import zmes_hook_helpers.common_params as g
import pyzm.ZMLog as zmlog
from inspect import getframeinfo,stack

class wrapperLogger():
    
    def __init__(self,name,dump_console):
       zmlog.init(name=name)
       self.dump_console = dump_console

    def debug(self, msg):
        idx = min(len(stack()), 1) 
        caller = getframeinfo(stack()[idx][0])
        zmlog.Debug(1,msg,caller)
        if (self.dump_console): print ('CONSOLE:'+msg)

    def info(self, msg):
        idx = min(len(stack()), 1) 
        caller = getframeinfo(stack()[idx][0])
        zmlog.Info(msg,caller)
        if (self.dump_console): print ('CONSOLE:'+msg)

    def error(self,msg):
        idx = min(len(stack()), 1) 
        caller = getframeinfo(stack()[idx][0])
        zmlog.Error(msg,caller)
        if (self.dump_console): print ('CONSOLE:'+msg)
    def setLevel(self,level):
        pass


def init(process_name=None, dump_console=False):
    g.logger = wrapperLogger(name=process_name, dump_console=dump_console)

