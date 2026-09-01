import { useEffect, useRef } from 'react';

export type ConfirmRequest = {
  title: string;
  body: string;
  confirmLabel: string;
  tone?: 'danger' | 'normal';
  onConfirm: () => void;
};

export function ConfirmDialog(props: { request: ConfirmRequest | null; onCancel: () => void }) {
  const dialogRef = useRef<HTMLDialogElement>(null);

  useEffect(() => {
    const dialog = dialogRef.current;
    if (!dialog) {
      return;
    }
    if (props.request && !dialog.open) {
      dialog.showModal();
    }
    else if (!props.request && dialog.open) {
      dialog.close();
    }
  }, [props.request]);

  return (
    <dialog
      ref={dialogRef}
      className="confirm-dialog"
      role="alertdialog"
      aria-labelledby="confirm-dialog-title"
      aria-describedby="confirm-dialog-body"
      onCancel={props.onCancel}
    >
      {props.request ? (
        <div className="confirm-dialog__content">
          <span className="eyebrow">Confirm</span>
          <h2 id="confirm-dialog-title">{props.request.title}</h2>
          <p id="confirm-dialog-body">{props.request.body}</p>
          <div className="confirm-dialog__actions">
            <button
              className="btn"
              onClick={props.onCancel}
              autoFocus={props.request.tone === 'danger'}
            >
              取消
            </button>
            <button
              className={`btn ${props.request.tone === 'danger' ? 'btn--danger' : 'btn--primary'}`}
              onClick={() => {
                const confirm = props.request?.onConfirm;
                props.onCancel();
                confirm?.();
              }}
              autoFocus={props.request.tone !== 'danger'}
            >
              {props.request.confirmLabel}
            </button>
          </div>
        </div>
      ) : null}
    </dialog>
  );
}
