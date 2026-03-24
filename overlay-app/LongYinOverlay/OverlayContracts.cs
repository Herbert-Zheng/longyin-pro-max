using System.Text.Json.Serialization;

namespace LongYinOverlay;

internal sealed class OverlayState
{
    public int Version { get; set; }
    public string UpdatedAtUtc { get; set; } = string.Empty;
    public string StatusMessage { get; set; } = string.Empty;
    public string StatusChangedAtUtc { get; set; } = string.Empty;
    public string WorldDate { get; set; } = string.Empty;
    public int SaveSlotId { get; set; } = -1;
    public int OwnedShopCount { get; set; }
    public int? PlayerMoney { get; set; }
    public bool InShop { get; set; }
    public string? ShopKey { get; set; }
    public string? ShopName { get; set; }
    public bool ShopOwned { get; set; }
    public bool CanBuyShop { get; set; }
    public int BuyPrice { get; set; }
    public string? PurchasedOn { get; set; }
    public string? LastProcessedRequestId { get; set; }
}

internal sealed class OverlayCommand
{
    public int Version { get; set; } = 1;
    public string RequestId { get; set; } = Guid.NewGuid().ToString("N");
    public string Action { get; set; } = string.Empty;
    public string? ShopKey { get; set; }
}
