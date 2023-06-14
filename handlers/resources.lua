local retry_common = require("Lib/retry_common")

return retry_common.only_retry_handler(5, {200, 301, 302})
