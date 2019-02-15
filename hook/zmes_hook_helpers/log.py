import logging
import logging.handlers
import zmes_hook_helpers.common_params as g

def init(process_name='process_name'):
    g.logger = logging.getLogger(__name__)
    g.logger.setLevel(logging.INFO)
    handler = logging.handlers.SysLogHandler('/dev/log')
    formatter = logging.Formatter(process_name+':[%(process)d]: %(levelname)s [%(message)s]')
    handler.formatter = formatter
    g.logger.addHandler(handler)

