import type { ConfigurationStatus } from '../../shared/launcher-state';

export function StatusCenter(props: {
  message: string;
  working?: string | null;
  configuration: ConfigurationStatus;
  dirtyScopes?: readonly string[];
}) {
  const dirtyScopes = props.dirtyScopes ?? [];

  return (
    <section className="status-strip" aria-label="当前状态" aria-live="polite" aria-atomic="true">
      <div className="status-strip__label">当前状态</div>
      <div className="status-strip__value">{props.working ?? props.message}</div>
      <div className="status-strip__badges">
        {props.configuration.key === 'saved' ? (
          <span className="state-badge state-badge--good">{props.configuration.detail}</span>
        ) : null}
        {props.configuration.key !== 'saved' && props.configuration.key !== 'dirty' ? (
          <span className="state-badge state-badge--warn">{props.configuration.detail}</span>
        ) : null}
        {props.configuration.key === 'dirty'
          ? dirtyScopes.map((scope) => (
              <span className="state-badge state-badge--warn" key={scope}>
                {scope}
              </span>
            ))
          : null}
      </div>
    </section>
  );
}
