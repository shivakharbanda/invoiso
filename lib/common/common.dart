import 'package:flutter/widgets.dart';
import 'package:invoiso/l10n/app_localizations.dart';
import 'package:invoiso_core/common/common.dart';

export 'package:invoiso_core/common/common.dart';
export 'pdf_styles.dart';

/// Shared "X-Small"/"Small"/"Medium"/"Large"/"Extra Large" labels for
/// [LogoSize], [SignatureSize], [ThermalCompanyNameSize] and [PdfFontSize] —
/// same wording, so one ARB key set covers all of them.
String _genericSizeLabel(BuildContext context, String key) {
  final l10n = AppLocalizations.of(context)!;
  switch (key) {
    case 'xsmall':
      return l10n.sizeXSmallLabel;
    case 'small':
      return l10n.sizeSmallLabel;
    case 'medium':
      return l10n.sizeMediumLabel;
    case 'xlarge':
      return l10n.sizeXLargeLabel;
    default:
      return l10n.sizeLargeLabel;
  }
}

String pageSizeLabel(BuildContext context, PageSize size) {
  final l10n = AppLocalizations.of(context)!;
  switch (size) {
    case PageSize.a4:
      return l10n.pageSizeA4Label;
    case PageSize.a5:
      return l10n.pageSizeA5Label;
    case PageSize.a6:
      return l10n.pageSizeA6Label;
    case PageSize.thermal80:
      return l10n.pageSizeThermal80Label;
    case PageSize.thermal58:
      return l10n.pageSizeThermal58Label;
  }
}

String dateFormatOptionLabel(BuildContext context, DateFormatOption option) {
  final l10n = AppLocalizations.of(context)!;
  switch (option) {
    case DateFormatOption.ddmmyyyy:
      return l10n.dateFormatDdmmyyyyLabel;
    case DateFormatOption.mmddyyyy:
      return l10n.dateFormatMmddyyyyLabel;
    case DateFormatOption.ddMmmyyyy:
      return l10n.dateFormatDdMmmyyyyLabel;
    case DateFormatOption.yyyymmdd:
      return l10n.dateFormatYyyymmddLabel;
  }
}

String logoSizeLabel(BuildContext context, LogoSize size) =>
    _genericSizeLabel(context, size.key);

String signatureSizeLabel(BuildContext context, SignatureSize size) =>
    _genericSizeLabel(context, size.key);

String thermalCompanyNameSizeLabel(
        BuildContext context, ThermalCompanyNameSize size) =>
    _genericSizeLabel(context, size.key);

String pdfFontSizeLabel(BuildContext context, PdfFontSize size) =>
    _genericSizeLabel(context, size.key);
