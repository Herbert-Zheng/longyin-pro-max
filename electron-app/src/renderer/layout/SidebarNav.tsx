export type SidebarNavItem<Key extends string = string> = {
  key: Key;
  label: string;
  eyebrow: string;
  description: string;
};

export type SidebarStatusRow = {
  label: string;
  value: string;
  tone?: 'good' | 'warn';
};

export function SidebarNav<Key extends string>(props: {
  items: readonly SidebarNavItem<Key>[];
  activeKey: Key;
  onNavigate: (key: Key) => void;
  statusRows: readonly SidebarStatusRow[];
}) {
  return (
    <aside className="sidebar">
      <div className="sidebar__brand">
        <span className="eyebrow">龙胤立志传 Pro Max</span>
        <h1>控制台</h1>
        <p>按功能分区管理模组；保存、启动和运行状态始终集中在当前工作区。</p>
      </div>

      <nav className="sidebar__nav" aria-label="主导航">
        {props.items.map((item) => (
          <button
            key={item.key}
            className={`nav-item ${props.activeKey === item.key ? 'nav-item--active' : ''}`}
            onClick={() => props.onNavigate(item.key)}
            aria-current={props.activeKey === item.key ? 'page' : undefined}
            title={item.description}
          >
            <span className="nav-item__eyebrow">{item.eyebrow}</span>
            <strong>{item.label}</strong>
            <span className="nav-item__desc">{item.description}</span>
          </button>
        ))}
      </nav>

      <div className="sidebar__panel" aria-label="应用概况">
        {props.statusRows.map((row) => (
          <div className="sidebar__panel-row" key={row.label}>
            <span>{row.label}</span>
            <strong className={row.tone ? `text-${row.tone}` : undefined}>{row.value}</strong>
          </div>
        ))}
      </div>
    </aside>
  );
}
