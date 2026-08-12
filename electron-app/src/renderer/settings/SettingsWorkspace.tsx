import { useEffect, useRef, useState } from 'react';
import type { VisibleSettings } from '../../shared/types';
import { BattleSettingsPage } from './BattleSettingsPage';
import { ExpTalentSettingsPage } from './ExpTalentSettingsPage';
import { SettingsSearch } from './SettingsSearch';
import { SocialTeamSettingsPage } from './SocialTeamSettingsPage';
import { TradeCraftSettingsPage } from './TradeCraftSettingsPage';
import type { SettingChangeHandler, SettingsPage } from './types';
import { WorldExploreSettingsPage } from './WorldExploreSettingsPage';

export type SettingsWorkspaceProps = {
  page: SettingsPage;
  settings: VisibleSettings;
  onSettingChange: SettingChangeHandler;
};

export function SettingsWorkspace({ page, settings, onSettingChange }: SettingsWorkspaceProps) {
  const [query, setQuery] = useState('');
  const [resultCount, setResultCount] = useState(0);
  const [totalCount, setTotalCount] = useState(0);
  const contentRef = useRef<HTMLDivElement>(null);
  const pageProps = { settings, onSettingChange };
  let content = null;

  useEffect(() => {
    setQuery('');
  }, [page]);

  useEffect(() => {
    const normalized = query.trim().toLocaleLowerCase('zh-CN');
    const cards = [...(contentRef.current?.querySelectorAll<HTMLElement>('[data-searchable-card]') ?? [])];
    setTotalCount(cards.length);
    let matches = 0;
    for (const card of cards) {
      const visible = normalized.length === 0 || (card.textContent ?? '').toLocaleLowerCase('zh-CN').includes(normalized);
      card.hidden = !visible;
      if (visible) {
        matches += 1;
      }
    }
    setResultCount(matches);
  }, [page, query]);

  switch (page) {
    case 'expTalent':
      content = <ExpTalentSettingsPage {...pageProps} />;
      break;
    case 'worldExplore':
      content = <WorldExploreSettingsPage {...pageProps} />;
      break;
    case 'tradeCraft':
      content = <TradeCraftSettingsPage {...pageProps} />;
      break;
    case 'socialTeam':
      content = <SocialTeamSettingsPage {...pageProps} />;
      break;
    case 'battle':
      content = <BattleSettingsPage {...pageProps} />;
      break;
  }

  return (
    <section className="settings-workspace" aria-label="设置工作区">
      <SettingsSearch value={query} onChange={setQuery} resultCount={resultCount} totalCount={totalCount} />
      <div ref={contentRef}>{content}</div>
      {query.trim() && resultCount === 0 ? (
        <div className="empty-state" role="status">当前页没有匹配的设置，换个关键词试试。</div>
      ) : null}
    </section>
  );
}
