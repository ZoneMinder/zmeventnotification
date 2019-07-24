import logging
import logging.handlers
import zmes_hook_helpers.common_params as g
import pyzmutils.logger as zmlog
from inspect import getframeinfo,stack

class wrapperLogger(zmlog.ZMLogger):
    
    def debug(self, msg):
        idx = min(len(stack()), 1) 
        caller = getframeinfo(stack()[idx][0])
        self.Debug(1,msg,caller)

    def info(self, msg):
        idx = min(len(stack()), 1) 
        caller = getframeinfo(stack()[idx][0])
        self.Info(msg,caller)
    def error(self,msg):
        idx = min(len(stack()), 1) 
        caller = getframeinfo(stack()[idx][0])
        self.Error(msg,caller)
    def setLevel(self,level):
        pass


def init(process_name=None):
    g.logger = wrapperLogger(name=process_name)

