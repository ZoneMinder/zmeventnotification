import logging
import logging.handlers
import zmes_hook_helpers.common_params as g
import pyzm.ZMLog as zmlog
from inspect import getframeinfo,stack

class wrapperLogger():
    
    def __init__(self,name):
       zmlog.init(name=name)

    def debug(self, msg):
        idx = min(len(stack()), 1) 
        caller = getframeinfo(stack()[idx][0])
        zmlog.Debug(1,msg,caller)

    def info(self, msg):
        idx = min(len(stack()), 1) 
        caller = getframeinfo(stack()[idx][0])
        zmlog.Info(msg,caller)
    def error(self,msg):
        idx = min(len(stack()), 1) 
        caller = getframeinfo(stack()[idx][0])
        zmlog.Error(msg,caller)
    def setLevel(self,level):
        pass


def init(process_name=None):
    g.logger = wrapperLogger(name=process_name)

