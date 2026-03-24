using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Windows;
using System.Windows.Input;
using System.Windows.Threading;

namespace LongYinOverlay;

public partial class MainWindow : Window
{
    private const int OverlayProtocolVersion = 1;
    private static readonly TimeSpan PollInterval = TimeSpan.FromMilliseconds(250);
    private static readonly TimeSpan StateFreshFor = TimeSpan.FromSeconds(2.5);
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
        WriteIndented = true
    };

    private readonly DispatcherTimer _pollTimer;
    private readonly string _ipcRoot;
    private readonly string _statePath;
    private readonly string _commandPath;
    private OverlayState? _currentState;
    private string _lastSubmittedRequestId = string.Empty;

    public MainWindow()
    {
        InitializeComponent();

        _ipcRoot = ResolveBridgeRoot();
        _statePath = Path.Combine(_ipcRoot, "codex.longyin.overlay-state.json");
        _commandPath = Path.Combine(_ipcRoot, "codex.longyin.overlay-command.json");

        _pollTimer = new DispatcherTimer
        {
            Interval = PollInterval
        };
        _pollTimer.Tick += PollTimerOnTick;

        Loaded += OnLoaded;
        Closed += (_, _) => _pollTimer.Stop();
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        PositionFixedOverlay();
        UpdateView(null, connected: false, stale: true);
        _pollTimer.Start();
    }

    private void PollTimerOnTick(object? sender, EventArgs e)
    {
        var state = TryReadState(out var isFresh);
        _currentState = state;
        UpdateView(state, connected: state != null, stale: !isFresh);
    }

    private OverlayState? TryReadState(out bool isFresh)
    {
        isFresh = false;
        if (!File.Exists(_statePath))
        {
            return null;
        }

        try
        {
            var state = JsonSerializer.Deserialize<OverlayState>(File.ReadAllText(_statePath), JsonOptions);
            if (state == null || state.Version != OverlayProtocolVersion)
            {
                return null;
            }

            isFresh = DateTime.TryParse(state.UpdatedAtUtc, out var updatedAtUtc) &&
                DateTime.UtcNow - updatedAtUtc <= StateFreshFor;
            return state;
        }
        catch
        {
            return null;
        }
    }

    private void UpdateView(OverlayState? state, bool connected, bool stale)
    {
        var effectivelyConnected = connected && !stale;
        ConnectionText.Text = effectivelyConnected ? "已连接到游戏模组" : "等待游戏模组状态";
        ConnectionText.Foreground = effectivelyConnected
            ? UiBrushes.Success
            : UiBrushes.Warning;

        if (state == null)
        {
            StatusText.Text = "请先启动游戏并载入存档。";
            DateText.Text = "日期: 未知";
            SaveSlotText.Text = "存档槽: 未绑定";
            MoneyText.Text = "金钱: 未知";
            ShopText.Text = "当前店铺: 未知";
            OwnershipText.Text = "产权状态: 未知";
            HintText.Text = "外部浮窗正在等待插件写入状态文件。";
            BuyButton.Content = "常驻显示测试中";
            BuyButton.IsEnabled = false;
            return;
        }

        StatusText.Text = string.IsNullOrWhiteSpace(state.StatusMessage)
            ? "状态同步中..."
            : state.StatusMessage;
        DateText.Text = $"日期: {Fallback(state.WorldDate, "未知")}";
        SaveSlotText.Text = state.SaveSlotId >= 0
            ? $"存档槽: {state.SaveSlotId}"
            : "存档槽: 未绑定";
        MoneyText.Text = state.PlayerMoney.HasValue
            ? $"金钱: {state.PlayerMoney.Value}"
            : "金钱: 未知";

        if (state.InShop)
        {
            ShopText.Text = $"当前店铺: {Fallback(state.ShopName, "未知店铺")}";
            OwnershipText.Text = state.ShopOwned
                ? string.IsNullOrWhiteSpace(state.PurchasedOn)
                    ? "产权状态: 你已买下此店"
                    : $"产权状态: 你已买下此店 ({state.PurchasedOn})"
                : $"产权状态: 未买下 | 价格: {state.BuyPrice}";
        }
        else
        {
            ShopText.Text = "当前店铺: 未进入店铺";
            OwnershipText.Text = $"已买店铺数: {state.OwnedShopCount}";
        }

        if (stale)
        {
            HintText.Text = "模组状态超过 2.5 秒未更新，请确认游戏仍在运行且插件已加载。";
            BuyButton.Content = "状态已过期";
            BuyButton.IsEnabled = false;
            return;
        }

        if (!state.InShop)
        {
            HintText.Text = "进入任意店铺后，这里会显示买断按钮和产权状态。";
            BuyButton.Content = "进入店铺后可买断";
            BuyButton.IsEnabled = false;
            return;
        }

        if (state.ShopOwned)
        {
            HintText.Text = "这间店的产权已经属于当前存档。";
            BuyButton.Content = "你已拥有这间店";
            BuyButton.IsEnabled = false;
            return;
        }

        if (!state.CanBuyShop)
        {
            HintText.Text = $"当前银钱不足，买店需要 {state.BuyPrice} 文钱。";
            BuyButton.Content = $"银钱不足 ({state.PlayerMoney ?? 0}/{state.BuyPrice})";
            BuyButton.IsEnabled = false;
            return;
        }

        if (!string.IsNullOrWhiteSpace(state.LastProcessedRequestId) &&
            string.Equals(state.LastProcessedRequestId, _lastSubmittedRequestId, StringComparison.Ordinal))
        {
            _lastSubmittedRequestId = string.Empty;
        }

        HintText.Text = "点击按钮后，插件会直接扣钱并写入当前存档槽对应的模组店铺档案。";
        BuyButton.Content = $"买下这间店 ({state.BuyPrice} 文钱)";
        BuyButton.IsEnabled = string.IsNullOrWhiteSpace(_lastSubmittedRequestId);
    }

    private void BuyButton_Click(object sender, RoutedEventArgs e)
    {
        if (_currentState == null ||
            !_currentState.InShop ||
            _currentState.ShopOwned ||
            !_currentState.CanBuyShop ||
            string.IsNullOrWhiteSpace(_currentState.ShopKey))
        {
            return;
        }

        try
        {
            Directory.CreateDirectory(_ipcRoot);
            var command = new OverlayCommand
            {
                Action = "buy-shop",
                ShopKey = _currentState.ShopKey
            };
            WriteJsonAtomically(_commandPath, command);
            _lastSubmittedRequestId = command.RequestId;
            StatusText.Text = "买店指令已发送，等待游戏确认...";
            BuyButton.IsEnabled = false;
        }
        catch (Exception ex)
        {
            StatusText.Text = $"发送买店指令失败：{ex.Message}";
        }
    }

    private void RootBorder_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ButtonState != MouseButtonState.Pressed)
        {
            return;
        }

        try
        {
            DragMove();
        }
        catch
        {
        }
    }

    private void PositionFixedOverlay()
    {
        try
        {
            var workArea = SystemParameters.WorkArea;
            Left = Math.Max(12d, workArea.Right - Width - 24d);
            Top = Math.Max(12d, workArea.Top + 24d);
        }
        catch
        {
        }
    }

    private static void WriteJsonAtomically(string path, OverlayCommand payload)
    {
        var tempPath = path + ".tmp";
        File.WriteAllText(tempPath, JsonSerializer.Serialize(payload, JsonOptions));
        File.Move(tempPath, path, true);
    }

    private static string ResolveBridgeRoot()
    {
        var baseDirectory = AppContext.BaseDirectory;
        var directConfig = Path.Combine(baseDirectory, "..", "BepInEx", "config");
        var normalizedDirectConfig = Path.GetFullPath(directConfig);
        if (Directory.Exists(normalizedDirectConfig))
        {
            return normalizedDirectConfig;
        }

        var fallbackConfig = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "LongYinProMaxOverlay");
        return fallbackConfig;
    }

    private static string Fallback(string? value, string fallback)
    {
        return string.IsNullOrWhiteSpace(value) ? fallback : value.Trim();
    }
}

internal static class UiBrushes
{
    internal static readonly System.Windows.Media.Brush Success =
        new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(166, 214, 153));

    internal static readonly System.Windows.Media.Brush Warning =
        new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(209, 177, 106));
}
