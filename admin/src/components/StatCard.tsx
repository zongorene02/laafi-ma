export default function StatCard({
  label,
  value,
  hint,
}: {
  label: string;
  value: string | number;
  hint?: string;
}) {
  return (
    <div className="rounded-2xl bg-white p-5 shadow-sm">
      <p className="text-sm font-medium text-gray-600">{label}</p>
      <p className="mt-2 text-3xl font-bold text-gray-900 tabular-nums">
        {typeof value === "number" ? value.toLocaleString("fr-FR") : value}
      </p>
      {hint && <p className="mt-1 text-xs text-gray-500">{hint}</p>}
    </div>
  );
}
