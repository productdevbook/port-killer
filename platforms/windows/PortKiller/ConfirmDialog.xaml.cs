using System.Windows;

namespace PortKiller;

public partial class ConfirmDialog : Window
{
    public bool Result { get; private set; }

    public ConfirmDialog(string message, string details, string title = "Confirm Action")
    {
        InitializeComponent();
        TitleText.Text = title;
        MessageText.Text = message;
        DetailsText.Text = details;
    }

    private void YesButton_Click(object sender, RoutedEventArgs e)
    {
        Result = true;
        Close();
    }

    private void NoButton_Click(object sender, RoutedEventArgs e)
    {
        Result = false;
        Close();
    }
}
