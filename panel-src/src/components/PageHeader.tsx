import { ReactNode } from "react";

interface PageHeaderProps {
  title: string;
  description?: string;
  actions?: ReactNode;
}

export function PageHeader({ title, description, actions }: PageHeaderProps) {
  return (
    <div className="page-heading mb-6">
      <div className="page-heading-copy min-w-0">
        <h1 className="page-title text-xl sm:text-2xl font-bold tracking-tight">{title}</h1>
        {description && (
          <p className="text-sm text-muted-foreground mt-1">{description}</p>
        )}
      </div>
      {actions && (
        <div className="page-heading-actions flex items-center flex-wrap gap-2 shrink-0">{actions}</div>
      )}
    </div>
  );
}
