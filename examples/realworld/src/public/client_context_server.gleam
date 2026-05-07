import public/client_context.{type ClientContext}
import server_context.{type ServerContext}

pub fn from_session(
  server_context: ServerContext,
  session_id: String,
  _hostname: String,
) -> #(ClientContext, ServerContext) {
  #(server_context.from_session(server_context, session_id), server_context)
}
