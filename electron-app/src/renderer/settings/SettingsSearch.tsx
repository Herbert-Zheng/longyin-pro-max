export function SettingsSearch(props: {
  value: string;
  onChange: (value: string) => void;
  resultCount: number;
  totalCount: number;
}) {
  return (
    <div className="settings-search" role="search">
      <label className="settings-search__field">
        <span className="settings-search__label">搜索当前页设置</span>
        <input
          className="input"
          type="search"
          value={props.value}
          onChange={(event) => props.onChange(event.target.value)}
          placeholder="例如：刷新、官府仓库、好感"
        />
      </label>
      <span className="settings-search__count" aria-live="polite">
        {props.value.trim() ? `找到 ${props.resultCount} / ${props.totalCount} 个分组` : `${props.totalCount} 个设置分组`}
      </span>
    </div>
  );
}
