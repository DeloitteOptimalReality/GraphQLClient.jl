"""
    output_debug(verbose)

Use to control whether or not a message should be printed that
can be considered as a debug level message.
"""
output_debug(verbose) = verbose >= 2

"""
    output_info(verbose)

Use to control whether or not a message should be printed that
can be considered as a info level message.
"""
output_info(verbose) = verbose >= 1