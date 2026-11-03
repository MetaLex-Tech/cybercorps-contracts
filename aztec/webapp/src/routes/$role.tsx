import { createFileRoute } from '@tanstack/react-router';
import { lazy, Suspense } from 'react';

// The page runs the user's wallet, so it renders in the browser only.
const App = lazy(() => import('../client/App'));

export const Route = createFileRoute('/$role')({
  ssr: false,
  component: function RolePage() {
    const { role } = Route.useParams();
    return (
      <Suspense fallback={<p>Loading…</p>}>
        <App role={role} />
      </Suspense>
    );
  },
});
