import 'package:invoiso_core/database/company_info_service.dart';
import 'package:invoiso_core/models/company_info.dart';
import 'package:invoiso_core/repositories/company_info_repository.dart';

class SqliteCompanyInfoRepository implements CompanyInfoRepository {
  @override
  Future<CompanyInfo?> getCompanyInfo() => CompanyInfoService.getCompanyInfo();
  @override
  Future<int> insertCompanyInfo(CompanyInfo info) =>
      CompanyInfoService.insertCompanyInfo(info);
  @override
  Future<int> updateCompanyInfo(CompanyInfo info) =>
      CompanyInfoService.updateCompanyInfo(info);
}
