using System;
using System.Text.Json.Serialization;

namespace PortKiller.Models;

/// <summary>
/// A port being monitored for status changes.
/// Users can configure notifications when a watched port starts or stops.
/// </summary>
public record WatchedPort
{
    /// <summary>
    /// Unique identifier for this watched port
    /// </summary>
    [JsonPropertyName("id")]
    public Guid Id { get; init; } = Guid.NewGuid();

    /// <summary>
    /// The port number being watched
    /// </summary>
    [JsonPropertyName("port")]
    public int Port { get; init; }

    /// <summary>
    /// Whether to send a notification when this port becomes active
    /// </summary>
    [JsonPropertyName("notifyOnStart")]
    public bool NotifyOnStart { get; init; } = true;

    /// <summary>
    /// Whether to send a notification when this port becomes inactive
    /// </summary>
    [JsonPropertyName("notifyOnStop")]
    public bool NotifyOnStop { get; init; } = true;
}
