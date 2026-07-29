<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Routing\Route;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\Route as Router;
use Illuminate\Support\Str;

class GenerateBrunoCollection extends Command
{
    protected $signature = 'bruno:generate
                            {--output=docs/bruno : Output directory for the collection}
                            {--environment=local : Environment name}
                            {--url=http://localhost : Base URL for the environment}
                            {--prefix=api : URI prefix used to filter and build route URLs}
                            {--group-by=namespace : Grouping strategy: namespace, uri-segment, none}
                            {--namespace=App\\Features : Base namespace to extract group from (used with --group-by=namespace)}
                            {--watch : Watch route files and regenerate on changes}
                            {--interval=2 : Polling interval in seconds (used with --watch)}
                            {--force : Overwrite existing files}';

    protected $description = 'Generate a Bruno API collection from registered routes';

    public function handle(): int
    {
        if ($this->option('watch')) {
            return $this->watch();
        }

        return $this->generate();
    }

    private function generate(): int
    {
        $outputDir = base_path($this->option('output'));

        if (is_dir($outputDir) && ! $this->option('force')) {
            if (! $this->confirm("Directory [{$outputDir}] already exists. Overwrite existing files?")) {
                return self::FAILURE;
            }
        }

        $this->createDirectories($outputDir);
        $this->writeCollectionConfig($outputDir);
        $this->writeEnvironment($outputDir);
        $this->writeRouteFiles($outputDir);

        $this->info('Bruno collection generated at ['.base_path($this->option('output')).']');

        return self::SUCCESS;
    }

    private function watch(): never
    {
        $interval = (int) $this->option('interval');
        $snapshots = $this->snapshotRouteFiles();

        $this->info('Watching route files... (Ctrl+C to stop)');
        $this->newLine();

        $this->spawnGenerate();

        while (true) {
            sleep($interval);

            $current = $this->snapshotRouteFiles();

            if ($current !== $snapshots) {
                $changed = array_keys(array_diff($current, $snapshots));
                foreach ($changed as $file) {
                    $this->line('  <comment>changed</comment>  '.Str::after($file, base_path('/')));
                }
                $this->spawnGenerate();
                $snapshots = $current;
            }
        }
    }

    // Spawns a fresh PHP process so new routes are picked up on every regeneration.
    private function spawnGenerate(): void
    {
        $args = [
            '--output='.$this->option('output'),
            '--environment='.$this->option('environment'),
            '--url='.$this->option('url'),
            '--prefix='.$this->option('prefix'),
            '--group-by='.$this->option('group-by'),
            '--namespace='.$this->option('namespace'),
            '--force',
            '--no-interaction',
        ];

        $cmd = implode(' ', [
            escapeshellarg(PHP_BINARY),
            escapeshellarg(base_path('artisan')),
            'bruno:generate',
            ...array_map('escapeshellarg', $args),
        ]);

        exec($cmd);

        $this->info('['.now()->format('H:i:s').'] Regenerated → '.base_path($this->option('output')));
    }

    /** @return array<string, int> filepath => mtime */
    private function snapshotRouteFiles(): array
    {
        $files = array_merge(
            glob(base_path('routes/*.php')) ?: [],
            glob(base_path('app/Features/*/routes*.php')) ?: [],
            glob(base_path('app/Features/*/*/routes*.php')) ?: [],
        );

        $snapshot = [];
        foreach ($files as $file) {
            $snapshot[$file] = (int) filemtime($file);
        }

        return $snapshot;
    }

    private function createDirectories(string $outputDir): void
    {
        foreach ([$outputDir, "{$outputDir}/environments"] as $dir) {
            if (! is_dir($dir)) {
                mkdir($dir, 0755, true);
            }
        }
    }

    private function writeCollectionConfig(string $outputDir): void
    {
        $config = json_encode([
            'version' => '1',
            'name' => config('app.name', 'Laravel API'),
            'type' => 'collection',
        ], JSON_PRETTY_PRINT);

        file_put_contents("{$outputDir}/bruno.json", $config.PHP_EOL);
    }

    private function writeEnvironment(string $outputDir): void
    {
        $env = $this->option('environment');
        $url = $this->option('url');

        $content = <<<BRU
        vars {
          baseUrl: {$url}
        }
        BRU;

        file_put_contents("{$outputDir}/environments/{$env}.bru", $content.PHP_EOL);
    }

    private function writeRouteFiles(string $outputDir): void
    {
        $routes = $this->getApiRoutes();

        if ($routes->isEmpty()) {
            $this->warn('No routes found matching prefix "'.$this->option('prefix').'".');

            return;
        }

        $grouped = $routes->groupBy($this->resolveGroup(...));
        $seq = 1;

        foreach ($grouped as $group => $groupRoutes) {
            $groupDir = $group !== '_root'
                ? "{$outputDir}/{$group}"
                : $outputDir;

            if (! is_dir($groupDir)) {
                mkdir($groupDir, 0755, true);
            }

            foreach ($groupRoutes as $route) {
                $filename = $this->resolveFilename($route);
                $filepath = "{$groupDir}/{$filename}.bru";

                file_put_contents($filepath, $this->buildBruContent($route, $seq++));
            }
        }
    }

    /** @return Collection<int, Route> */
    private function getApiRoutes(): Collection
    {
        $prefix = $this->option('prefix');

        return collect(Router::getRoutes()->getRoutes())
            ->filter(fn (Route $route) => Str::startsWith($route->uri(), $prefix))
            ->values();
    }

    private function resolveGroup(Route $route): string
    {
        return match ($this->option('group-by')) {
            'namespace' => $this->groupByNamespace($route),
            'uri-segment' => $this->groupByUriSegment($route),
            default => '_root',
        };
    }

    private function groupByNamespace(Route $route): string
    {
        $controller = $route->getAction('controller');

        if (! $controller) {
            return '_root';
        }

        $ns = preg_quote($this->option('namespace'), '/');

        if (preg_match("/{$ns}\\\\(\w+)\\\\/", $controller, $matches)) {
            return $matches[1];
        }

        return '_root';
    }

    private function groupByUriSegment(Route $route): string
    {
        $prefix = preg_quote($this->option('prefix'), '/');
        $uri = preg_replace("/^{$prefix}\\/?/", '', $route->uri());
        $uri = preg_replace('/^v\d+\//', '', $uri);

        $segments = array_values(array_filter(explode('/', $uri)));
        $first = collect($segments)->first(fn (string $s) => ! Str::startsWith($s, '{'));

        return $first ?? '_root';
    }

    private function resolveFilename(Route $route): string
    {
        $controller = $route->getAction('controller');
        $method = Str::lower(collect($route->methods())->first(fn (string $m) => $m !== 'HEAD') ?? 'get');

        if ($controller && preg_match('/(\w+Controller)$/', $controller, $matches)) {
            $name = Str::slug(Str::snake(preg_replace('/Controller$/', '', $matches[1])));

            return "{$method}-{$name}";
        }

        $prefix = preg_quote($this->option('prefix'), '/');
        $uri = preg_replace("/^{$prefix}(?:\/v\d+)?\/?/", '', trim($route->uri(), '/'));
        $uri = $uri === '' ? 'index' : $uri;
        $name = Str::slug(str_replace(['{', '}'], ['by-', ''], $uri));

        return "{$method}-{$name}";
    }

    private function buildBruContent(Route $route, int $seq): string
    {
        $prefix = $this->option('prefix');
        $method = Str::lower(
            collect($route->methods())->first(fn (string $m) => $m !== 'HEAD') ?? 'get'
        );

        $rest = Str::after($route->uri(), $prefix);
        $uri = "{{baseUrl}}/{$prefix}{$rest}";
        $uri = preg_replace('/(?<!\{)\{(\w+)\}(?!\})/', ':$1', $uri);

        $name = $route->getName() ?? $this->humanizeName($route->uri(), $method);
        $hasBody = \in_array($method, ['post', 'put', 'patch']);
        $body = $hasBody ? 'json' : 'none';

        $lines = [
            'meta {',
            "  name: {$name}",
            '  type: http',
            "  seq: {$seq}",
            '}',
            '',
            "{$method} {",
            "  url: {$uri}",
            "  body: {$body}",
            '  auth: none',
            '}',
        ];

        if ($hasBody) {
            $lines[] = '';
            $lines[] = 'body:json {';
            $lines[] = '  {}';
            $lines[] = '}';
        }

        return implode(PHP_EOL, $lines).PHP_EOL;
    }

    private function humanizeName(string $uri, string $method): string
    {
        $prefix = $this->option('prefix');
        $clean = preg_replace('/[{}]/', '', $uri);
        $clean = preg_replace('/^'.preg_quote($prefix, '/').'(?:\/v\d+)?\//', '', $clean);
        $clean = str_replace('/', ' ', trim($clean, '/'));
        $clean = $clean === '' ? 'index' : $clean;

        return Str::title("{$method} {$clean}");
    }
}
