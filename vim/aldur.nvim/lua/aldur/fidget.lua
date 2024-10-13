require("fidget").setup {
    fmt = {
        max_messages = 3,
        task = -- function to format each task line
        function(task_name, message, percentage)
            if message == "Started" then
                message = "..."
            elseif message == "Completed" then
                return nil -- Avoid spam
            else
                if message then
                    message = string.format(": %s", string.lower(message))
                end
            end
            return string.format("%s%s %s", task_name, message, percentage and
                                     string.format(" (%s%%)", percentage) or "")
        end
    }
}
