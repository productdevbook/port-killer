pub struct Utils;

impl Utils {
    /// Parse an address:port string.
    ///
    /// Handles multiple address formats:
    /// - IPv4: "127.0.0.1:3000" or "*:8080"
    /// - IPv6: "\[::1]:3000" or "\[fe80::1]:8080"
    pub fn parse_address(address: &str) -> Option<(String, u16)> {
        if address.starts_with('[') {
            // IPv6 format: [::1]:3000
            let bracket_end = address.find(']')?;
            if bracket_end + 1 >= address.len() || address.as_bytes()[bracket_end + 1] != b':' {
                return None;
            }
            let addr = &address[..=bracket_end];
            let port_str = &address[bracket_end + 2..];
            let port: u16 = port_str.parse().ok()?;
            Some((addr.to_string(), port))
        } else {
            // IPv4 format: 127.0.0.1:3000 or *:8080
            let last_colon = address.rfind(':')?;
            let addr = &address[..last_colon];
            let port_str = &address[last_colon + 1..];
            let port: u16 = port_str.parse().ok()?;
            let addr = if addr.is_empty() { "*" } else { addr };
            Some((addr.to_string(), port))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_ipv4_address() {
        let (addr, port) = Utils::parse_address("127.0.0.1:3000").unwrap();
        assert_eq!(addr, "127.0.0.1");
        assert_eq!(port, 3000);

        let (addr, port) = Utils::parse_address("*:8080").unwrap();
        assert_eq!(addr, "*");
        assert_eq!(port, 8080);
    }

    #[test]
    fn test_parse_ipv6_address() {
        let (addr, port) = Utils::parse_address("[::1]:3000").unwrap();
        assert_eq!(addr, "[::1]");
        assert_eq!(port, 3000);

        let (addr, port) = Utils::parse_address("[fe80::1]:8080").unwrap();
        assert_eq!(addr, "[fe80::1]");
        assert_eq!(port, 8080);
    }
}
