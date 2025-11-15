use std::collections::HashSet;

/// Tool filtering configuration for controlling which MCP tools are exposed
#[derive(Debug, Clone)]
pub struct ToolFilterConfig {
    pub mode: FilterMode,
    pub tools: HashSet<String>,
}

/// Filtering mode for tool visibility
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FilterMode {
    /// Only expose listed tools
    Whitelist,
    /// Hide listed tools, expose all others
    Blacklist,
    /// No filtering - expose all tools (default)
    All,
}

impl ToolFilterConfig {
    /// Create a new tool filter configuration
    pub fn new(mode: FilterMode, tools: Vec<String>) -> Self {
        Self {
            mode,
            tools: tools.into_iter().collect(),
        }
    }

    /// Check if a tool should be included based on the filter configuration
    pub fn should_include_tool(&self, tool_name: &str) -> bool {
        match self.mode {
            FilterMode::All => true,
            FilterMode::Whitelist => self.tools.contains(tool_name),
            FilterMode::Blacklist => !self.tools.contains(tool_name),
        }
    }
}

impl Default for ToolFilterConfig {
    fn default() -> Self {
        Self {
            mode: FilterMode::All,
            tools: HashSet::new(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_filter_mode_all_includes_everything() {
        let config = ToolFilterConfig::default();
        assert!(config.should_include_tool("any_tool"));
        assert!(config.should_include_tool("another_tool"));
    }

    #[test]
    fn test_whitelist_mode_only_includes_listed_tools() {
        let config = ToolFilterConfig::new(
            FilterMode::Whitelist,
            vec!["read_buffer".to_string(), "navigate".to_string()],
        );

        assert!(config.should_include_tool("read_buffer"));
        assert!(config.should_include_tool("navigate"));
        assert!(!config.should_include_tool("lsp_definition"));
        assert!(!config.should_include_tool("execute_lua"));
    }

    #[test]
    fn test_blacklist_mode_excludes_listed_tools() {
        let config = ToolFilterConfig::new(
            FilterMode::Blacklist,
            vec!["execute_lua".to_string(), "buffer_diagnostics".to_string()],
        );

        assert!(!config.should_include_tool("execute_lua"));
        assert!(!config.should_include_tool("buffer_diagnostics"));
        assert!(config.should_include_tool("read_buffer"));
        assert!(config.should_include_tool("navigate"));
    }

    #[test]
    fn test_empty_whitelist_includes_nothing() {
        let config = ToolFilterConfig::new(FilterMode::Whitelist, vec![]);

        assert!(!config.should_include_tool("any_tool"));
    }

    #[test]
    fn test_empty_blacklist_includes_everything() {
        let config = ToolFilterConfig::new(FilterMode::Blacklist, vec![]);

        assert!(config.should_include_tool("any_tool"));
        assert!(config.should_include_tool("another_tool"));
    }
}
