//! Stateless MCP adapter; HTTP middleware authenticates each request independently.
use crate::{
    data::{self, Range, TOOLS},
    state::AgentState,
};
use rmcp::{ErrorData, RoleServer, ServerHandler, model::*, service::RequestContext};
use serde_json::json;
use zoop_storage::AgentConnection;
#[derive(Clone, Debug)]
pub(crate) struct AgentMcp(pub AgentState);
fn grant(ctx: &RequestContext<RoleServer>) -> Result<AgentConnection, ErrorData> {
    ctx.extensions
        .get::<axum::http::request::Parts>()
        .and_then(|p| p.extensions.get::<AgentConnection>())
        .cloned()
        .ok_or_else(|| ErrorData::invalid_request("Agent authentication required", None))
}
impl ServerHandler for AgentMcp {
    fn get_info(&self) -> ServerConfig {
        ServerConfig::new(ServerCapabilities::builder().enable_tools().build()).with_instructions("Read-only access to the consenting user's Zoop data. Dates use the connection timezone. Missing values are not zero. Do not present associations as causes or wellness estimates as diagnoses. Never request passwords or keys in chat.")
    }
    async fn list_tools(
        &self,
        _: Option<PaginatedRequestParams>,
        ctx: RequestContext<RoleServer>,
    ) -> Result<ListToolsResult, ErrorData> {
        let g = grant(&ctx)?;
        let schema = json!({"type":"object","properties":{"from":{"type":"string","format":"date","description":"Inclusive local date; at most 90 days per call"},"to":{"type":"string","format":"date","description":"Inclusive local date"}},"additionalProperties":false});
        let schema = schema.as_object().cloned().unwrap_or_default();
        Ok(ListToolsResult::with_all_items(
            TOOLS
                .iter()
                .filter(|(_, _, scope)| scope.is_empty() || g.scopes.iter().any(|s| s == scope))
                .map(|(name, description, _)| {
                    Tool::new(*name, *description, schema.clone()).with_annotations(
                        ToolAnnotations::from_raw(
                            None,
                            Some(true),
                            Some(false),
                            Some(true),
                            Some(false),
                        ),
                    )
                })
                .collect(),
        ))
    }
    async fn call_tool(
        &self,
        r: CallToolRequestParams,
        ctx: RequestContext<RoleServer>,
    ) -> Result<CallToolResponse, ErrorData> {
        let g = grant(&ctx)?;
        let range: Range =
            serde_json::from_value(serde_json::Value::Object(r.arguments.unwrap_or_default()))
                .map_err(|_| {
                    ErrorData::invalid_params(
                        "Use from/to dates only; account and device are fixed by consent.",
                        None,
                    )
                })?;
        match data::execute(&self.0, &g, &r.name, range).await {
            Ok(v) => Ok(CallToolResult::structured(v).into()),
            Err(e) => Ok(CallToolResult::structured_error(json!({"error":e.to_string()})).into()),
        }
    }
}
