// Topp Dawg Gaming - isolated, loopback-only Chrome DevTools WebSocket client.
// Uses a strict RFC 6455 handshake. No NuGet, driver, browser extension, or service.
// Compatible with the .NET Framework runtime included in Windows PowerShell 5.1.
using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;

public sealed class TDGLoopbackWebSocket : IDisposable
{
    private TcpClient client;
    private NetworkStream stream;
    private const int MaxMessageBytes = 700000;
    private static byte[] RandomBytes(int count)
    {
        byte[] output = new byte[count];
        using (RandomNumberGenerator rng = RandomNumberGenerator.Create()) { rng.GetBytes(output); }
        return output;
    }

    public TDGLoopbackWebSocket(string advertisedWebSocketUrl, int localPort)
    {
        if (localPort < 1 || localPort > 65535) throw new ArgumentException("Invalid local debugging port.");
        Uri advertised;
        if (!Uri.TryCreate(advertisedWebSocketUrl, UriKind.Absolute, out advertised) ||
            !String.Equals(advertised.Scheme, "ws", StringComparison.OrdinalIgnoreCase) ||
            !advertised.AbsolutePath.StartsWith("/devtools/page/", StringComparison.Ordinal))
            throw new ArgumentException("Browser did not supply a valid page-debugging URL.");
        // NEVER trust the advertised hostname: connect only to local IPv4 loopback.
        client = new TcpClient(AddressFamily.InterNetwork);
        try
        {
            IAsyncResult connect = client.BeginConnect(IPAddress.Loopback, localPort, null, null);
            try
            {
                if (!connect.AsyncWaitHandle.WaitOne(5000)) throw new IOException("Loopback TCP connection timed out.");
                client.EndConnect(connect);
            }
            finally { connect.AsyncWaitHandle.Close(); }
            stream = client.GetStream();
            stream.ReadTimeout = 12000;
            stream.WriteTimeout = 12000;
            string key = Convert.ToBase64String(RandomBytes(16));
            string path = advertised.PathAndQuery;
            string request = "GET " + path + " HTTP/1.1\r\n" +
                "Host: 127.0.0.1:" + localPort + "\r\n" +
                "Upgrade: websocket\r\n" +
                "Connection: Upgrade\r\n" +
                "Sec-WebSocket-Key: " + key + "\r\n" +
                "Sec-WebSocket-Version: 13\r\n\r\n";
            byte[] raw = Encoding.ASCII.GetBytes(request);
            stream.Write(raw, 0, raw.Length);
            string headers = ReadHeaders();
            string[] lines = headers.Split(new string[] { "\r\n" }, StringSplitOptions.None);
            if (lines.Length < 1 || !lines[0].StartsWith("HTTP/1.1 101 ", StringComparison.Ordinal))
                throw new IOException("DevTools WebSocket handshake returned " +
                    (lines.Length > 0 ? lines[0] : "an empty response") +
                    ". A browser or security policy rejected the local upgrade.");
            string accept = "";
            foreach (string line in lines)
            {
                if (line.StartsWith("Sec-WebSocket-Accept:", StringComparison.OrdinalIgnoreCase))
                    accept = line.Substring("Sec-WebSocket-Accept:".Length).Trim();
            }
            string expected;
            using (SHA1 sha = SHA1.Create())
                expected = Convert.ToBase64String(sha.ComputeHash(Encoding.ASCII.GetBytes(
                    key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11")));
            if (!String.Equals(accept, expected, StringComparison.Ordinal))
                throw new IOException("The local debugging server returned an invalid WebSocket handshake.");
        }
        catch { Dispose(); throw; }
    }

    private string ReadHeaders()
    {
        MemoryStream buffer = new MemoryStream();
        int a = 0, b = 0, c = 0;
        while (buffer.Length < 16384)
        {
            int value = stream.ReadByte();
            if (value < 0) throw new IOException("Browser closed before completing its handshake.");
            buffer.WriteByte((byte)value);
            if (a == 13 && b == 10 && c == 13 && value == 10)
                return Encoding.ASCII.GetString(buffer.ToArray());
            a = b; b = c; c = value;
        }
        throw new IOException("Browser handshake headers were too large.");
    }

    private byte[] ReadExactly(int count)
    {
        byte[] bytes = new byte[count];
        int offset = 0;
        while (offset < count)
        {
            int read = stream.Read(bytes, offset, count - offset);
            if (read <= 0) throw new IOException("Browser closed the debugging connection.");
            offset += read;
        }
        return bytes;
    }

    private void SendFrame(byte opcode, byte[] payload)
    {
        if (payload.Length > MaxMessageBytes) throw new IOException("Debugging message too large.");
        MemoryStream packet = new MemoryStream();
        packet.WriteByte((byte)(0x80 | opcode));
        ulong len = (ulong)payload.Length;
        if (len <= 125) packet.WriteByte((byte)(0x80 | (byte)len));
        else if (len <= 65535)
        {
            packet.WriteByte(0x80 | 126);
            packet.WriteByte((byte)(len >> 8));
            packet.WriteByte((byte)len);
        }
        else
        {
            packet.WriteByte(0x80 | 127);
            for (int j = 7; j >= 0; j--) packet.WriteByte((byte)(len >> (8 * j)));
        }
        byte[] mask = RandomBytes(4);
        packet.Write(mask, 0, 4);
        byte[] encoded = new byte[payload.Length];
        for (int i = 0; i < payload.Length; i++) encoded[i] = (byte)(payload[i] ^ mask[i % 4]);
        packet.Write(encoded, 0, encoded.Length);
        byte[] frame = packet.ToArray();
        stream.Write(frame, 0, frame.Length);
    }

    public void SendText(string text)
    {
        if (stream == null) throw new ObjectDisposedException("TDGLoopbackWebSocket");
        SendFrame(1, Encoding.UTF8.GetBytes(text));
    }

    public string ReceiveText(int timeoutMilliseconds)
    {
        if (stream == null) throw new ObjectDisposedException("TDGLoopbackWebSocket");
        stream.ReadTimeout = Math.Max(1000, Math.Min(30000, timeoutMilliseconds));
        MemoryStream message = new MemoryStream();
        bool started = false;
        for (int frameIndex = 0; frameIndex < 128; frameIndex++)
        {
            byte[] head = ReadExactly(2);
            bool fin = (head[0] & 0x80) != 0;
            int opcode = head[0] & 0x0F;
            ulong length = (ulong)(head[1] & 0x7F);
            bool masked = (head[1] & 0x80) != 0;
            if (length == 126)
            {
                byte[] two = ReadExactly(2);
                length = ((ulong)two[0] << 8) | two[1];
            }
            else if (length == 127)
            {
                byte[] eight = ReadExactly(8);
                length = 0;
                for (int i = 0; i < 8; i++) length = (length << 8) | eight[i];
            }
            if (length > MaxMessageBytes || message.Length + (long)length > MaxMessageBytes)
                throw new IOException("Browser response exceeded the maximum expected size.");
            byte[] mask = masked ? ReadExactly(4) : null;
            byte[] data = ReadExactly((int)length);
            if (masked) for (int i = 0; i < data.Length; i++) data[i] ^= mask[i % 4];
            if (opcode == 8) throw new IOException("Browser closed the debugging connection.");
            if (opcode == 9) { SendFrame(10, data); continue; }
            if (opcode == 10) continue;
            if (opcode == 1) { message.SetLength(0); started = true; }
            else if (opcode != 0 || !started) continue;
            message.Write(data, 0, data.Length);
            if (fin) return Encoding.UTF8.GetString(message.ToArray());
        }
        throw new IOException("Browser sent too many fragmented WebSocket frames.");
    }

    public void Dispose()
    {
        if (stream != null) { try { stream.Dispose(); } catch { } stream = null; }
        if (client != null) { try { client.Close(); } catch { } client = null; }
    }
}
