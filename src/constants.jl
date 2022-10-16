# GQL over WS Protocol constants
# https://github.com/apollographql/subscriptions-transport-ws/blob/master/PROTOCOL.md

const GQL_CLIENT_CONNECTION_INIT = "connection_init"
const GQL_SERVER_CONNECTION_ACK = "connection_ack"
const GQL_SERVER_CONNECTION_ERROR = "connection_error"
const GQL_SERVER_CONNECTION_KEEP_ALIVE = "ka"
const GQL_CLIENT_START = "start"
const GQL_CLIENT_STOP = "stop"
const GQL_CLIENT_CONNECTION_TERMINATE = "connection_terminate"
const GQL_SERVER_DATA = "data"
const GQL_SERVER_ERROR = "error"
const GQL_SERVER_COMPLETE = "complete"

# Subscription tracker
const SUBSCRIPTION_STATUS_OPEN = "open"
const SUBSCRIPTION_STATUS_ERROR = "errored"
const SUBSCRIPTION_STATUS_CLOSED = "closed"

# New GQL over WS constanst
# https://github.com/enisdenjo/graphql-ws/blob/master/PROTOCOL.md

const GQLWS_CLIENT_INIT = "connection_init"
const GQLWS_SERVER_CONNECTION_ACK = "connection_ack"
const GQLWS_BI_PING = "ping"
const GQLWS_BI_PONG = "pong"
const GQLWS_CLIENT_SUBSCRIBE = "subscribe"
const GQLWS_SERVER_NEXT = "next"
const GQLWS_SERVER_ERROR = "error"
const GQLWS_BI_COMPLETE = "complete"


