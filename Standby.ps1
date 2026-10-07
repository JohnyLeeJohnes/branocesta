# Standby.ps1: PowerShell nastartovaný dopředu, "záloha". Brána ho pouští schovaný hned po svém otevření
# (Start-Standby v Branocesta.ps1). Načte si WPF a čeká; po kliknutí na Spustit mu brána pošle cestu ke
# skriptu aplikace a aplikace se rozběhne tady. Start PowerShellu a WPF, který jinak trvá nejdéle, má tou
# dobou už za sebou.
#
# Cesta přijde jedním řádkem na standardním vstupu, v Base64. Když brána skončí a nic nepustí, vstup se
# zavře a záloha skončí taky.
#
# Aplikace má běžet stejně, jako když ji pouští její zástupce. Proto se tu nenastavuje nic, co by od
# tohohle skriptu zdědila ($ErrorActionPreference), a proměnné mají jména, která se s jejími nepotkají.

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, Microsoft.VisualBasic

# Rozcvička. Všechno, co WPF a PowerShell dělají poprvé, je pomalé: čtení XAML, šablony prvků, písma, okno
# pro Windows, přístup PowerShellu k vlastnostem prvků. Tady se to odbude na okně, které se nikdy neukáže,
# a aplikace pak totéž udělá zhruba za polovinu času. Prvky jsou ty, ze kterých jsou okna aplikací poskládaná.
# Blok má vlastní proměnné, takže po něm nic nezůstane; když se nepovede, aplikace se jen rozběhne pomaleji.
& {
    try {
        $window = [Windows.Markup.XamlReader]::Parse(@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="400" Height="300" FontFamily="Segoe UI" UseLayoutRounding="True" TextOptions.TextFormattingMode="Display">
    <Window.Resources>
        <SolidColorBrush x:Key="Brush" Color="#12111C"/>
        <Style x:Key="Button" TargetType="Button">
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="8">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Bd" Property="Opacity" Value="0.8"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    <StackPanel>
        <TextBlock x:Name="Text" Text="Aa" TextWrapping="Wrap" FontWeight="SemiBold"/>
        <TextBlock FontFamily="Segoe MDL2 Assets" Text="&#xE72C;"/>
        <Button x:Name="Button" Style="{StaticResource Button}" Content="Aa" Background="{StaticResource Brush}"/>
        <ToggleButton Content="Aa"/>
        <RadioButton Content="Aa"/>
        <CheckBox Content="Aa"/>
        <TextBox Text="1"/>
        <ProgressBar Height="2" Value="50"/>
        <Viewbox Width="20" Height="20">
            <Canvas Width="256" Height="256">
                <Rectangle Width="256" Height="256" RadiusX="60" RadiusY="60">
                    <Rectangle.Fill>
                        <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
                            <GradientStop Color="#2C3968" Offset="0"/>
                            <GradientStop Color="#0B0F1E" Offset="1"/>
                        </LinearGradientBrush>
                    </Rectangle.Fill>
                </Rectangle>
                <Path Fill="{StaticResource Brush}" Data="M 170,68 C 173.8,88.2 173.8,88.2 194,92 Z"/>
            </Canvas>
        </Viewbox>
        <Grid>
            <Grid.ColumnDefinitions>
                <ColumnDefinition/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <Border BorderThickness="1" BorderBrush="{StaticResource Brush}" CornerRadius="4"/>
        </Grid>
        <DockPanel/>
        <UniformGrid Rows="1"/>
        <ScrollViewer Height="10"/>
        <ItemsControl/>
    </StackPanel>
</Window>
'@)
        # Okno vznikne, ale neukáže se. To je důležité: brána i aplikace hledají proces, který má okno vidět,
        # a tenhle se za něj nesmí vydávat.
        $null = [Windows.Interop.WindowInteropHelper]::new($window).EnsureHandle()
        $window.Content.Measure([Windows.Size]::new(400, 300))
        $window.Content.Arrange([Windows.Rect]::new(0, 0, 400, 300))
        $window.Content.UpdateLayout()
        [Windows.Media.Imaging.RenderTargetBitmap]::new(400, 300, 96, 96, [Windows.Media.PixelFormats]::Pbgra32).Render($window.Content)
        $window.FindName('Text').Text = 'Bb'
        $window.FindName('Button').Add_Click({ })
        $window.FindName('Button').Visibility = 'Visible'
        $null = $window.FindResource('Brush')
        $null = [Windows.Threading.DispatcherTimer]::new()
        $window.Close()
    } catch { }
}

$standbyScript = ''
# Před cestou může přijít značka kódování (BOM), kterou .NET do roury zapíše sám; do Base64 nepatří.
try { $standbyScript = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(([Console]::In.ReadLine() -replace '[^A-Za-z0-9+/=]'))) }
catch { }
# Vstup skončil bez cesty: brána se zavřela a nic nepustila.
if (-not $standbyScript) { return }

# Aplikace běží ve své složce. Tím ji zároveň drží, takže ji brána za běhu nepřepíše ani nesmaže.
[Environment]::CurrentDirectory = Split-Path $standbyScript
Set-Location -LiteralPath (Split-Path $standbyScript)
& $standbyScript
