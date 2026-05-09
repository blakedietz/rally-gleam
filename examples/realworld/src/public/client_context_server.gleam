import public/client_context.{type ClientContext}
import server_context.{type ServerContext}

pub fn from_session(
  server_context server_context: ServerContext,
  session_id session_id: String,
  hostname hostname: String,
) -> #(ClientContext, ServerContext) {
  let _hostname = hostname
  #(server_context.from_session(server_context: server_context, session_id: session_id), server_context)
}
