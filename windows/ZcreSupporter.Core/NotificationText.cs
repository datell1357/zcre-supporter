namespace ZcreSupporter.Core;

public static class NotificationText
{
    public static string Limit(string text, int maximum)
    {
        var length = Math.Min(text.Length, maximum);
        if (length > 0 && length < text.Length && char.IsHighSurrogate(text[length - 1]) && char.IsLowSurrogate(text[length])) length--;
        return text[..length];
    }
}
